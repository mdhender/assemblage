# Assemblage Deployment

`asmd` speaks plain HTTP on loopback and never terminates TLS. A reverse proxy
terminates it and guarantees TLS 1.3 or better. This is true in production and
simulated in development, so there is one serving model rather than two.

See `docs/DESIGN.md` §11, "Serving model", for the four requirements this
imposes on the application: the public origin is configuration rather than
inference, session cookies are `Secure` regardless of the local scheme,
forwarded headers are trusted only from configured proxy addresses, and CSRF
protection is `net/http.CrossOriginProtection` with the public origin registered
as trusted.

## Development

**Caddy runs as a machine-wide Homebrew service. Never run it yourself** — not
`caddy run`, not `caddy start`, not `caddy trust`, and above all not
`caddy run --config deploy/Caddyfile.dev`. `Caddyfile.dev` in this directory is
an **EXAMPLE ONLY**: it documents the shape of the proxy and is not the
configuration this machine serves.

Running `caddy` as your own user account mints a second internal CA root with
the same subject name as the service's and trusts it. Two same-subject anchors
make chain building non-deterministic, so HTTPS to `*.localhost:8443` starts
failing at random and clearing it needs `sudo` keychain surgery.

The service reads `/opt/homebrew/etc/Caddyfile`, which already terminates TLS
for `https://htmx-app.localhost:8443` and proxies it to `127.0.0.1:18443`. Its
CA lives in `/opt/homebrew/var/lib/caddy/pki/`. Start only `asmd`:

```sh
brew services list | grep caddy    # expect "started"; if not, ask a human
mkdir -p var                       # no command creates a directory; this one is yours
go run ./cmd/asmdb init --db ./var                 # creates ./var/assemblage.db
go run ./cmd/asmd serve --db ./var --addr 127.0.0.1:18443 --env development --timeout 60m
```

`--db` names an existing directory; the database inside it is always
`assemblage.db`. `asmd` neither creates nor migrates it, so a fresh checkout
needs the `asmdb init` line above once.

Check it is up with <https://htmx-app.localhost:8443/healthz>. There is no page
at the root: the HTML UI was removed in issue #3 and `asmd` serves the JSON API,
the preview mount, and the job workers. Point `earl` at the same origin.

The host name is the shared vhost for every Go + HTMX application on this
laptop, not a claim about this one, which is why it kept the name.

When diagnosing local TLS, inspect the chain actually served on the wire and
test with `/usr/bin/curl`; Homebrew's `openssl` and `curl` use their own CA
bundles and will disagree with the macOS keychain.

`--env development` enables the `/__development/*` routes, which let an
automated agent log in without a password and stop the server over HTTP. There
is no tag involved: the environment is the only switch, so `go run ./cmd/asmd`
works without a build step. In any other environment the routes are never
registered. (The `production` tag under "Building for the server" is a
placement check for release binaries; it gates no routes.) `--timeout` is
ungated and useful anywhere; always pass one in development so an abandoned
server does not sit on the SQLite lock.

`earl` points at the same public URL, not at the Go listener:

```sh
go run ./cmd/earl login --server https://htmx-app.localhost:8443
```

Talking to `http://127.0.0.1:18443` directly bypasses the proxy and therefore
exercises a code path that does not exist in production. Do it only when
debugging the proxy itself.

## Production

Any proxy that terminates TLS 1.3+, sets the standard forwarded headers, and
passes `Origin` and `Sec-Fetch-*` through unmodified will do. The proxy owns
TLS configuration, HSTS, HTTP→HTTPS redirection, and certificates. `asmd` owns
none of them.

`deploy/Caddyfile.prod` and `deploy/nginx.conf` are worked examples of each, for
`assemblage.mdhenderson.com`. `deploy/PROVISIONING.md` is the first-time setup
of the droplet they run on; `deploy/assemblage.service` is the unit.

Everything `asmd` needs is a flag, plus one environment variable. **There is no
configuration file.** `docs/DESIGN.md` §11 lists a `--config FILE`, and
`cmd/asmd/main.go` says in a comment where it would be read; it is not
implemented, and a flag that is parsed and ignored is worse than no flag. Until
it exists, the unit file's `ExecStart` is the configuration:

| Flag | Value |
|---|---|
| `--addr` | a loopback address and port (default `127.0.0.1:18443`) |
| `--public-origin` | the browser-facing origin, scheme included |
| `--trusted-proxy` | CIDRs the proxy connects from (default `127.0.0.1/32`, `::1/128` — already right when the proxy is on the same host) |
| `--timeout` | optional graceful shutdown after a duration; `0`, the default, means never |
| `--db` | the directory holding `assemblage.db`; it must already exist |
| `--templates`, `--preview`, `--output` | optional directories that must already exist; without them the server renders, previews, and publishes nothing |
| `--workers` | background job workers in this process; `0` disables them |
| `$ASSEMBLAGE_ENV` | `production` — see below |

`ASSEMBLAGE_ENV=development` on a server is a complete authentication bypass: it
is what registers the `/__development/*` routes, and either of them logs anyone
in as anyone. The environment is the only gate on those routes, so this one
variable carries the whole weight. Set it in the unit file. Never set it in an
interactive shell profile, and never copy a development `.env` onto a server.

CI asserts that a server started with no `--env` and no `ASSEMBLAGE_ENV` returns
404 for every `/__development/*` route, and that the same routes are live under
`--env development`; those assertions gate release.

## Building for the server

Release binaries are built with `-tags production`. The tag adds one thing: a
`buildenv.Verify()` that each `main` calls at startup, which **panics unless
`ASSEMBLAGE_ENV` is exported as exactly `production`**. Binaries built without
the tag have the mirror check — they panic if `ASSEMBLAGE_ENV` *is*
`production`. A binary therefore cannot run on the wrong kind of machine without
saying so immediately, in the logs, at startup, rather than quietly serving the
wrong configuration. See `docs/DESIGN.md` §14, "The build/environment
interlock".

The tag gates **nothing else**. It adds no routes, removes no code, and changes
no behaviour beyond that one assertion.

`make release` is this loop, and is the one place in the repository that runs
`mkdir` — build output, not data:

```sh
mkdir -p deploy/linux/amd64
for c in asmd asmdb earl; do
    GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
        go build -tags production -trimpath -o deploy/linux/amd64/$c ./cmd/$c
done
```

`CGO_ENABLED=0` is correct here rather than merely convenient: the SQLite
driver is `zombiezen.com/go/sqlite`, which is pure Go, so there is nothing to
link and cross-compiling from a Mac needs no toolchain. If the driver ever
changes to a cgo one, this recipe stops being a one-liner — treat that as part
of the cost of the change.

Ship them:

```sh
rsync -av deploy/linux/amd64/ assemblage:/opt/assemblage/bin/
```

`assemblage` is a `~/.ssh/config` host alias for the droplet — see
`PROVISIONING.md`, step 1. There is deliberately no `--chmod=F755`: recent
macOS ships openrsync, which rejects it, and `make release` already leaves the
binaries `755` for `rsync -a` to preserve. `deploy/linux/` is build output and
is not committed.

**On a server that is already running, this `rsync` is not the first step.**
"Deploying a new version" below has the order, which is neither a plain
`systemctl restart` nor an upload followed by one: the backup is taken before
the binaries are replaced, because a backup is taken by a binary that agrees
with the database.

Two checks worth doing once, on the server, before the first restart:

```sh
/opt/assemblage/bin/asmd version                 # expect: panics, ASSEMBLAGE_ENV is not set
ASSEMBLAGE_ENV=production /opt/assemblage/bin/asmd version
```

The first panicking is the interlock working. If it prints a version instead,
the binary was built without `-tags production` and must not be deployed.

## Deploying a new version

The first deploy is `PROVISIONING.md`. Every one after it is four steps, and
they alternate between the two machines. Build on the Mac:

```sh
make check
make release
```

Stop the service and take the backup **on the droplet, with the binaries that
are already there**:

```sh
sudo systemctl stop assemblage
ASSEMBLAGE_ENV=production /opt/assemblage/bin/asmdb backup \
  --db /opt/assemblage/var --to "/opt/assemblage/backups/assemblage-$(date +%F).db"
```

Ship the new binaries, from the Mac:

```sh
rsync -av deploy/linux/amd64/ assemblage:/opt/assemblage/bin/
rsync -av --exclude=linux/ deploy/ assemblage:/opt/assemblage/deploy/
```

Migrate and start, on the droplet:

```sh
ASSEMBLAGE_ENV=production /opt/assemblage/bin/asmdb migrate status --db /opt/assemblage/var
ASSEMBLAGE_ENV=production /opt/assemblage/bin/asmdb migrate up --db /opt/assemblage/var
sudo systemctl start assemblage
```

**The order is the point, and three separate reasons hold it in place.**

*The backup is taken before the upload because it should not depend on which
binaries happen to be in place.* This step used to come after the upload, and
on the first deploy that carried a migration it refused: `asmdb backup` demanded
that the schema version match the number of migrations the binary embedded, and
uploading first is what made those disagree. That refusal is gone — `backup` now
asks only whether the file is this system's database (issue #25) — so either
order would work today. It stays here because the backup you want is of the
database as it is, taken before anything else on the machine has moved, and
because a step whose success depends on the order of two other steps is a step
that will fail again for a new reason.

*The service is stopped before the backup so that the file is exactly the state
the migration is about to act on.* `backup` does not need the service stopped —
`VACUUM INTO` takes its own read transaction and runs happily against a live
server — but a backup taken while `asmd` is still accepting writes is a backup
missing whatever arrived between it and the stop. Those are the edits somebody
would most want back.

*The service starts last because it cannot start earlier.* `asmd` requires
`user_version` to equal the number of migrations it embeds and refuses to start
otherwise (§13.4), so a new binary with a pending migration will not run — the
intended behaviour, not a bug to work around. The stop has to bracket the
migration anyway: `asmdb` and `asmd` would otherwise contend for the same SQLite
write lock.

The cost is that the `rsync` now happens inside the outage rather than before
it. That is tens of megabytes over one connection — seconds, on a service that
is already down for the migration — and it buys a deploy with no step that has
to be invented while the site is off.

`backup` prints the path, the size, and the `user_version`, and it says
`verified` only after opening what it wrote and checking it. Put that output in
the deploy log: a backup is a file nobody reads until the day it matters, and
that is the wrong day to find out it is zero bytes.

`/opt/assemblage/backups` must already exist — nothing in this system creates a
directory, and `PROVISIONING.md` §4 makes it. An existing file is refused
rather than replaced, so a second deploy on the same day needs `--overwrite`
and a moment's thought about which backup you would rather have.

To verify a backup later, name it directly:

```sh
ASSEMBLAGE_ENV=production /opt/assemblage/bin/asmdb check --file /opt/assemblage/backups/assemblage-2026-09-09.db
```

That works on a backup taken at any schema, including one older than the
binaries reading it (issue #25). `backup` and `check --file` ask whether the
file is this system's database and whether SQLite finds it sound; which schema
is inside it is reported rather than required. A backup outlives the binaries
that made it, and the file whose whole purpose is to be readable on the worst
day should not need a build that embeds exactly as many migrations as it did.

On a schema older than the queue — migration 0008 — the line reads
`stuck job leases: not checked (this schema predates the queue)` rather than
zero. It is not a fault; it is the check declining to report a number it could
not ask for.

**Restoring is a `cp` with the service stopped**, and deliberately not a
command:

```sh
sudo systemctl stop assemblage
cp /opt/assemblage/backups/assemblage-2026-09-09.db /opt/assemblage/var/assemblage.db
rm -f /opt/assemblage/var/assemblage.db-wal /opt/assemblage/var/assemblage.db-shm
ASSEMBLAGE_ENV=production /opt/assemblage/bin/asmdb check --db /opt/assemblage/var
sudo systemctl start assemblage
```

Run those as `deploy`, which owns `/opt/assemblage` and is the account the unit
runs as. Remove the write-ahead log and its index along with the database: they
belong to the one being replaced, and leaving them beside a different one is the
one way to turn a good backup into a corrupt database. The `check` before
starting is what tells you the restore landed. It also refuses outright if
`user_version` does not match the binary in `/opt/assemblage/bin`, which is what
restoring across a migration produces: put back the binaries that go with the
backup, or migrate the restored database up before starting.

Migrations are append-only, and the beta exception that once permitted a squash
is withdrawn (`DESIGN.md` §13.6). That is a promise to this server: the schema
version only ever goes up, so a database here is always either current or
behind, and behind is what `asmdb migrate up` is for. Nothing on this machine
should ever write `PRAGMA user_version` — if a database appears to be *ahead* of
the binaries in `/opt/assemblage/bin`, the binaries are the wrong ones, and the
fix is to deploy the right ones rather than to touch the database.

If the unit file or a proxy config changed in the same push, install it from
`/opt/assemblage/deploy/` and reload that service; the copies under `/etc` are
meant to be diffable against the originals shipped there.
