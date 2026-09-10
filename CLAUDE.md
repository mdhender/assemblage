# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Authoritative documents

Read these before changing anything; they are unusually complete and they win over
inference from the code.

- `docs/DESIGN.md` — what is being built and why. Every implementation decision
  traces to a numbered section (`DESIGN.md 8.2`). Where it and `docs/PLAN.md`
  disagree, DESIGN wins and PLAN gets fixed.
- `docs/PLAN.md` — milestones M0–M14, the sequencing graph, and the
  "definition of done" checklist a change must pass.
- `AGENTS.md` — repository rules: alpha workflow, versioning, migrations.
- Each package's `doc.go` states its purpose *and its permitted imports*. Read
  the `doc.go` before adding an import to a package.

- `docs/adrs/` — design notes that outlived the code that held them. Read one
  before rebuilding the thing it describes.

Code comments cite "invariant N" (1–23). There is no master list in the repo;
`grep -rn "invariant 8"` finds the places that state and enforce it. Invariant 23
(autofill) no longer has code: it was the HTML UI's, and is now
`docs/adrs/0001-autofill-policy-for-form-clients.md`.

**Names.** The commands are `asmd` (server), `asmdb` (database lifecycle), and
`earl` (API client); the database file is always `assemblage.db`; the
environment variable is `ASSEMBLAGE_ENV`. In prose, "assemblage" means this
application and "content management system" is spelled out when the generic
concept is meant — don't reintroduce the acronym. `deploy/README.md` references
`make check` / `make release`; there is no Makefile, so run the equivalent
commands by hand.

## Commands

```sh
go build ./...
go vet ./...
gofmt -l .                      # must print nothing
go test ./...                   # ~70s; cmd/asmd compiles the binaries
go test -race ./...
go test -short ./...            # skips the binary-building end-to-end tests
```

Single test / package:

```sh
go test ./internal/service -run TestCheckoutConflict -v
go test ./internal/render -run TestEngine -update   # rewrite golden files
```

`-update` exists in the packages with `testdata/*.golden` (`internal/render`,
`internal/domain`, `cmd/asmd`).

The tagged half of the build interlock is only exercised explicitly:

```sh
ASSEMBLAGE_ENV=production go test -tags production ./internal/buildenv
```

### Running locally

Caddy is a machine-wide Homebrew service that already terminates TLS for
`https://htmx-app.localhost:8443` → `127.0.0.1:18443`. **Never run `caddy`
yourself**; `deploy/Caddyfile.dev` is an example only. If it is not started, ask.

That host name is **not** this application's and must not be renamed: it is the
shared vhost for every Go + HTMX application on this laptop, and it kept the name
after issue #3 removed the HTML UI. Renaming it means editing a Caddyfile several
unrelated projects depend on.

```sh
mkdir -p var                                   # no command creates a directory
go run ./cmd/asmdb init --db ./var             # creates ./var/assemblage.db
go run ./cmd/asmdb seed --db ./var --demo
go run ./cmd/asmdb bootstrap admin --db ./var --email you@example.com --name You
go run ./cmd/asmd serve --db ./var --addr 127.0.0.1:18443 --env development --timeout 60m
go run ./cmd/asmd routes                       # the table the config actually produces
```

`ASSEMBLAGE_ENV` also selects which `.env` files load (`internal/dotenv`), and
each `main` resolves it through `config.Resolve` before flag parsing. It
defaults to `production` in both roles, so export it to load `.env.development*`
locally; `--env` governs the running server but not which files were read.

Always pass `--timeout` in development so an abandoned server does not sit on the
SQLite lock. With `--env development` two agent affordances exist:
`GET /__development/log-me-in/{email}?returnTo=` and
`GET|POST /__development/shut-it-down` (`internal/devroutes`). They are gated on
the resolved environment and nothing else — there is no build tag hiding them.
With no `returnTo` the login route answers the session token as text or JSON;
`returnTo` sets the cookie and redirects, which is how a browser-driving agent
reaches `/preview/{name}`.

`earl` talks to the public origin, not the Go listener:

```sh
go run ./cmd/earl login --server https://htmx-app.localhost:8443
```

Release binaries: `GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -tags production -trimpath ...`
(the driver is pure Go). The `production` tag gates nothing but a startup
assertion that `ASSEMBLAGE_ENV=production` is exported.

## Architecture

Four layers, dependencies point **downward only**:

```
transport           internal/api (JSON)
                            |
service             internal/service
                            |
domain              internal/domain   (types, invariants, pure functions)
                            |
storage             internal/store    (SQL, zombiezen)
```

- `domain` imports the standard library only — no `database/sql`, no `net/http`,
  no `time.Now`. A test asserts it.
- `store` holds **all** SQL and no business decisions.
- `service` owns transactions, writes events, enqueues jobs. A use case lives here.
- `api` parses a request, calls one service method, renders. It never touches
  `store`. There was a second transport, `internal/web` (HTML/HTMX), removed in
  issue #3; a transport is a *client* of the service, holding no state the API
  lacks and permitting no operation it does not expose, and one added later
  arrives with the test that says so.

`workflow`, `authz`, `publish`, `jobs`, `events` sit beside `service`: logic too
specific for `domain`, too reusable for one service method. `events` deliberately
does not import `store` (it names the methods it needs as an interface) because
`store`'s tests use `events`' constants.

Leaves that exist so siblings never import each other: `reqctx` (client address,
request id, identity — resolved once, in one middleware), `edge` (the single
error→HTTP-status mapping and the single session-cookie writer), `clock`, `ids`,
`config`, `buildenv`. `server` is the composition root: the route table (built by
a function, so `asmd routes` prints the real one) and the one shutdown path.

If a rule seems to require breaking the layering, the answer is almost always a
pure function in `domain` that both callers use.

### Rules that are enforced, not aspirational

- **No SQL string outside `internal/store`.** Tests check this.
- **No `time.Now()` outside `main` and `internal/clock`.** Everything takes a `Clock`.
- **`internal/workflow` is the only writer of `documents.state`.** `Available`
  and `Do` share one `check` function — the UI renders `Available`, a forged
  POST re-runs the identical checks inside the transaction. A refused move is
  drawn *disabled with its reason*, never omitted.
- **Every state-changing service method writes an event**, in the same
  transaction as the change. A method that returns without one is unfinished.
- **`asmd` never creates a directory, a database, or runs a migration.** It opens
  `DIR/assemblage.db`, requires `application_id == 0x41534D30` and
  `user_version ==` the number of embedded migrations, or it exits non-zero with
  no listener. Only `asmdb init` creates. `--db` names an existing *directory*;
  the file inside is always `assemblage.db`. The single exception to "nothing
  creates a directory" is the computed interior of the output tree
  (`internal/publish/tree.go`).
- **SQLite errors are classified by result code, never by message text**
  (`store.ConstraintError`, which answers to `domain.ErrConflict`).
- **Internal integer primary keys never leave `store`.** The API speaks `uid`
  (lowercase ULIDs from `internal/ids`).
- **A publish job pins a version id, never a document id.** Approving v5 for
  midnight publishes v5 even after v6 is checked in. This is the single most
  important test in the project.
- **Cookies are `Secure`, `HttpOnly`, `SameSite=Lax` unconditionally.** Never gate
  `Secure` on `r.TLS != nil` — it is always false behind the proxy.
- **`server.public_origin` is configuration**, never inferred from `Host`. It
  feeds absolute URLs, cookies, and the `net/http.CrossOriginProtection`
  trusted-origin list. `X-Forwarded-*` is honoured only from `trusted_proxies`.
- Routing is `net/http.ServeMux` only — no third-party router. CSRF is
  `net/http.CrossOriginProtection` (the reason Go 1.25 is a hard floor).

### Testing conventions

- `domain`: exhaustive table-driven unit tests.
- `store`: a real in-memory SQLite through the same create path, foreign keys on.
  Never a mock.
- `service`: public methods, real store, fake clock; assert on emitted events.
- `api`: `httptest`, asserting status, problem type, and body shape.
- End-to-end tests in `cmd/asmd` build the real binaries and drive `earl` against
  an `asmd` on a `t.TempDir()` database. **No test helper calls `os.MkdirAll`** —
  a helper that creates what the commands refuse to create is a hole in the rule.
- The concurrency tests that matter: two workers racing one job, lease expiry
  and `attempts`, two checkouts of one document, publish pinned to version 5.

## Repository rules (alpha)

From `AGENTS.md`:

- Work directly on `main`; no branches. Commits and pushes to `main` are
  pre-authorized when they follow the versioning rule.
- **Every commit containing code changes must bump `version.go`** in the same
  commit — patch for fixes, minor for features. Never bump for docs-only changes.
- Assign every GitHub issue and PR to `mdhender`; reference the issue in the
  commit message (`Fixes #1`).
- **Keep exactly one migration file.** Edit `internal/migrate/schema/0001_initial.sql`
  for schema changes instead of adding a file. This deliberately overrides
  `DESIGN.md` §13.6 ("migrations are append-only") for the duration of alpha.

Other conventions: every Go file carries the `// Copyright (c) 2026 Michael D
Henderson.` header (MIT); vendored third-party files keep their licence text
beside them. Nothing is vendored today — the last was HTMX, which went with the
UI in issue #3.

`.env` files load through `internal/dotenv` in precedence order
`.env.{env}.local`, `.env.local`, `.env.{env}`, `.env`; the `.local` files are
gitignored and are the only ones that may hold secrets.
