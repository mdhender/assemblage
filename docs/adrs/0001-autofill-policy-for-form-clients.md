# ADR 0001 — Autofill is denied by default on every form control

**Status.** Recorded for a future client. Nothing in this repository enforces it
today, because nothing in this repository draws a form.

**Context.** This was invariant 23, held by `internal/web` — the HTMX UI removed
in #3 — and enforced by a template walk in `internal/web/autofill_test.go`. The
rule was learned from a real defect rather than derived from a principle, so it
is written down here instead of being deleted with the templates. If assemblage
ever grows a client that draws forms, in whatever technology, this is what that
client should read before drawing its first one.

The API itself needs none of this. `earl` has no forms and no browser.

## The decision

**Deny by default. Opt in twice, deliberately, and say why in the markup.**

Every form control declared a policy. There was no third option: a control that
declared nothing was a test failure, because "nothing" is not neutral — it is
the browser guessing from the field's name and type.

### Denial is four attributes, not one

```html
autocomplete="off" data-1p-ignore data-lpignore="true" data-form-type="other"
```

`autocomplete` alone does not work. It is advisory in both directions: password
managers ignore it by policy, because sites spent years using it to break them
on purpose and the managers stopped believing it, and Chrome overrides it
wherever its own heuristics feel confident. The three `data-` attributes are
1Password's, LastPass's and Dashlane's documented opt-outs.

They look like vendor cruft. They are not — deleting them puts a fill prompt
back on top of the invitation form, and 1Password's is a banner that has to be
dismissed before anybody can type anything at all.

In the Go templates this was a helper returning `template.HTMLAttr`, which is
the type `html/template` trusts in attribute-name position; a plain `string`
would have been escaped into nonsense. A client in another technology will need
its own equivalent escape hatch, and should give it one name so the walk below
has something to look for.

### Only credential fields opt in

Two forms opted in, and only two: the login form and the invitation redemption
form. They are the only fields that hold the credentials of the person looking
at the screen, so filling them is the manager doing its job.

```html
<!-- login -->
<input type="email"    name="email"    autocomplete="username">
<input type="password" name="password" autocomplete="current-password">

<!-- invitation redemption -->
<input type="email"    name="email"    autocomplete="username">
<input type="text"     name="name"     autocomplete="name">
<input type="password" name="password" autocomplete="new-password">
<input type="password" name="confirm"  autocomplete="new-password">
```

A third such form would not be wrong on its face, but it should not appear
without somebody deciding it.

### An address that is not a credential is `type="text"` with `inputmode="email"`

The pair `type="email"` + `name="email"` is the exact signature Chrome's
heuristic and every password manager read as "this is your username". The
invitation form's address box has that shape and is the opposite thing: it holds
the address of somebody who does not have an account yet, so the one value it
can never usefully carry is the address of the person typing.

`type="text" inputmode="email"` keeps the `@` on a phone keyboard and denies the
heuristic its cue. Nothing is lost, because **validation was never the browser's
job**: `domain.ValidateEmail` is the check and always was — deliberately weak,
because the strong check is delivery.

## The half that matters is the enforcement

The policy is not "we fixed the invite box". It is "a field added next year
cannot quietly arrive undeclared". Two tests held that, and a future client
should reproduce both:

1. **Every control declares something.** Walk the templates, find the opening
   tag of every `input`, `textarea` and `select`, and fail on one carrying
   neither the denial helper nor an explicit `autocomplete` token. Skip the
   types a manager has nothing to put in — `hidden`, `checkbox`, `radio`,
   `submit`, `button`. Fail if the walk found no controls at all, or the test is
   asserting nothing.

2. **The opt-in list does not grow quietly.** A second test named the two
   credential forms and failed on an `autocomplete=` anywhere else, so adding a
   third is a conversation rather than a commit.

Both were source scans rather than rendering tests, on purpose. What has to hold
is a property of the template, not of one page's data; rendering every page
would need a fixture apiece and would still miss the branch no fixture reached.

What neither can check is the browser. Whether Chrome and 1Password actually
leave a field alone is something a person verifies by looking at it. The four
attributes are the best available answer rather than a guarantee — the managers
treat all of it as advisory — and that is precisely why the policy is
deny-by-default. The only field we can be sure a manager will not disturb is one
we never asked it to fill.

## Where this came from

`internal/web/autofill_test.go` and the "Autocomplete is denied by default"
passage of `docs/DESIGN.md` §12, both removed in #3. Recover the originals from
git history if the reasoning above ever needs its source; nothing outside this
file states the policy now.
