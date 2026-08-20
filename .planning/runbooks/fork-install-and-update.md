# Runbook — installing and updating GSD from this fork

**What this covers:** running GSD from your own fork instead of the published npm
package, so `local/*` features (skills, workflow patches, `gsd-core/` edits) survive.

**The model behind it** — why `working`/`local/*` exist, what each `.planning/` folder
holds — is in `CLAUDE.md`. This file is procedure only.

---

## The one rule

> **Never run `/gsd-update`.** It shells out to
> `npx -y --package=@opengsd/gsd-core@TAG` (`gsd-core/workflows/update.md:383-393`),
> which installs **upstream's** tree into `~/.claude` and silently drops every local
> feature. Use `make sync && make install` instead.

This fork *is* the install source: `bin/install.js` reads `path.join(__dirname, '..')`
(`:10000`) and writes to the target config dir. That is why the recursive `rmSync` over
`skills/gsd-*` (`:10823-10826`) is safe here — it is wipe-then-replace-**from this repo**,
not a destroy. It is also why a `gsd-`-prefixed skill is correct rather than dangerous,
*provided* the skill is committed here.

---

## Install

```bash
cd ~/Documents/git/personal/gsd-core
git checkout working          # the integrated set; a local/* branch installs ONE feature
make install                  # build + install into ~/.claude
```

Restart Claude Code afterwards — skills and agents are read at startup.

`make install` warns (does not block) if you are off `working` or the tree is dirty;
installing work-in-progress to test it is legitimate, installing it by accident is not.

### Rehearse first when it matters

```bash
make install-test             # installs to /tmp/gsd-fork-test, never touches ~/.claude
CLAUDE_CONFIG_DIR=/tmp/gsd-fork-test claude
```

Worth doing before your first global install, and any time a change touches `skills/`
or `agents/` — a global install replaces `~/.claude/skills/gsd-*` wholesale.

### Why `make build` is not optional

`gsd-core/bin/lib/` is `tsc` output — 178 `.cjs` files, **170 gitignored**, 11 tracked
(`tsconfig.build.json`: `rootDir: src` → `outDir: gsd-core/bin/lib`). A fresh or stale
checkout is missing them, and `bin/install.js` dies on `require`:

```
Error: Cannot find module '../gsd-core/bin/lib/install-scope.cjs'
```

`make install` and `make install-test` both depend on `build`, so you cannot forget it.
`build` additionally asserts `install-scope.cjs` exists afterwards rather than trusting
the exit code — a half-successful build otherwise passes silently.

**Always build after editing anything in `src/`.** The compiled lib is what actually
ships; editing `src/*.cts` alone changes nothing that runs.

---

## Update from upstream

```bash
make sync                     # sync-next + rebuild-working + push-working
make install                  # then reinstall from the rebuilt working
```

`make sync` expands to:

1. `sync-next` — `git checkout next && git fetch origin && git merge --ff-only origin/next`
2. `rebuild-working` — `git checkout -B working next`, then octopus-merge every `local/*`
3. `push-working` — `git push fork working --force-with-lease`

`rebuild-working` requires a clean tree (`guard-clean`). Commit or stash first.

### After a big upstream jump

Check whether upstream moved anything a `local/*` branch patches. Line numbers drift
silently — `.planning/todos/` records real cases (`ship.md` shifted +26 lines between
1.10.0 and 1.11.0 and gained a new `gh` call site).

```bash
git diff next working --stat          # what your features actually change
git log --oneline v1.11.0..next       # what upstream changed
make verify                           # tests + lint:ci + changeset lint
```

---

## Add a feature

```bash
make feature NAME=my-feature          # branches local/my-feature off next
# ...edit, commit on that branch...
make rebuild-working
make install
```

**Edit on the feature branch, never on `working`.** `working` is rebuilt from scratch on
every sync — anything committed directly to it is lost without warning. That is also what
keeps `git diff next local/<slug>` showing exactly one feature.

Revisiting a feature after upstream has moved:

```bash
make update-feature NAME=my-feature   # merges next into it; merge, don't rebase
```

---

## Contribute upstream

Contribution branches come off `next`, never off `working` or `local/*`:

```bash
make new-pr TYPE=fix ISSUE=1234 SLUG=short-desc
```

`next` is byte-identical to upstream and carries **zero** `.planning` entries, no
`CLAUDE.md`, and no `Makefile` — so none of your personal setup can leak into a PR. That
guarantee is why this fork does not need `/gsd-workspace --new`.

Before pushing:

```bash
make verify
```

Hard gates live in `.planning/reference/contributing-reference.md` — read it first.
Issue-first is non-negotiable: no code before a maintainer applies `confirmed-bug` /
`approved-enhancement` / `approved-feature`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Cannot find module '.../bin/lib/*.cjs'` | build output missing or stale | `make build` |
| `make: *** No rule to make target` | on a branch where `Makefile` is not tracked | `git checkout working` |
| `✗ uncommitted changes` from `rebuild-working` | `guard-clean` | commit or stash |
| Octopus merge conflict in `.gitignore` | two `local/*` branches editing one region | keep both sides; then move one out of the contested anchor so it stops recurring |
| A skill edit did not take effect | Claude Code caches at startup | restart it |
| Local features vanished from `~/.claude` | `/gsd-update` was run | `make install` to restore |

---

## Verify an install actually took

```bash
ls ~/.claude/skills | grep -c '^gsd-'     # compare against: ls skills | wc -l
cat ~/.claude/gsd-core/VERSION
```

Counts will not match exactly — `~/.claude/skills` also holds personal non-`gsd-` skills
(e.g. `mempalace-rooms`), which installs never touch (`bin/install.js:4046`: *"Non-gsd-\*
dirs and their agents/ content are never touched"*).
