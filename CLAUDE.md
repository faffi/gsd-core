# gsd-core — working notes (local, untracked — `.gitignore:7`)

## What this repo is

This **is** GSD's own source — the agents, skills, workflows, and `gsd-tools.cjs` that
this very session runs came from this repo. We use GSD to build GSD, but **not in-place
in this checkout** by default: `.planning/` was deliberately deleted from `next`
(`a52248cb`, 2026-02-08) and `CONTRIBUTING.md` gives zero guidance on running `/gsd-*`
here directly. On `next` that blanket ignore still stands (`.gitignore:33`); on this
fork's own branches it has been narrowed so todos and seeds ARE tracked — see below.

**Mechanism here: the branch model, NOT `/gsd-workspace --new`.** Upstream ignores
`.planning/` for package hygiene (`a52248cb` deleted it, 1,540 lines) and the documented
answer for contributors is `/gsd-workspace --new` — an isolated `.planning/` at
`~/gsd-workspaces/<name>/`, outside the repo. **That is the wrong tool for this fork.**

This checkout instead narrows the ignore on the `working` and `local/*` branches only
(`.gitignore:40-42`:
`.planning/*` plus `!.planning/todos/` and `!.planning/seeds/`), so todos and seeds are
tracked *in* the repo and travel through `fork` to the other machine. `next` keeps
upstream's blanket ignore byte-identical and carries zero `.planning` entries, so a
contribution branch cut off `next` cannot leak one — the same guarantee the workspace
buys, reached a different way.

A workspace would put `.planning/` outside git entirely, losing todo history and the
fork sync. Use one only for throwaway dogfooding that must not touch this checkout.
Full rationale + alternatives: `.planning/reference/contributing-reference.md` §0.

**`next` = pristine.** Treat it as the read-only mirror of upstream. If you need to see
what's actually shipped/current, diff against `next`, don't guess from a stale local
branch.

## Remotes & branches

- `origin` → `open-gsd/gsd-core` (upstream, real project) — pull-only, no write access
- `fork` → `faffi/gsd-core` (personal fork) — push target, PR source
- `next` — pristine tracking branch. Never commit here directly.
- `local/<feature-slug>` — one branch per personal feature, based off `next`. Source of
  truth for that feature's work; never intended to upstream unless explicitly promoted.
- `working` — **disposable integration branch, not a base.** Rebuilt on demand by merging
  whichever `local/*` branches are currently active on top of current `next`. Tracks
  `fork/working`, but nothing is ever committed to it directly.
- Contribution branches — always fresh off current `next`, one per approved issue,
  deleted after merge. Never built on top of `working` or `local/*`.

> **Naming note:** the standing branch is `working`, not `local` — git refs are
> filesystem-path-like, so a branch literally named `local` blocks creating any
> `local/<slug>` branch at all ("directory file conflict"), even an empty, never-touched
> `local`. This isn't a discipline thing — no amount of "just don't commit to `local`"
> fixes it, the branch's mere existence blocks the whole `local/*` namespace. Hence
> `working` for the one standing/aggregate branch, `local/<slug>` for everything else.

## Managing personal features (long-lived, revisited over time)

**Branch each feature off `next`, never off `working`.** `working` gets rebuilt from
scratch on every upstream pull — anything based on it would need rebasing on every single
pull, whether or not you're actually touching that feature.

```bash
# new feature
git checkout -b local/feature-slug next

# revisiting a feature after next has moved — merge, don't rebase, to keep its
# history stable and avoid cascading into your other feature branches
git checkout local/feature-slug && git merge next

# rebuild the working branch from whichever features you want active
git checkout -B working next
git merge local/feature-a local/feature-b
git push fork working --force-with-lease
```

Edit a feature by checking out `local/<slug>` directly and committing there — never edit
on `working` and merge down. That's what keeps `git diff next local/<slug>` showing exactly
that one feature, nothing else, which is also your upgrade path: to contribute a mature
feature, rebase/cherry-pick *that one branch* onto a fresh `fix/NNN-slug`/`feat/NNN-slug`
off current `next` — **after** the issue is opened and approved, not before.

## `.planning/` — what each folder is for

Upstream ignores `.planning/` wholesale (`a52248cb` deleted its own, 1,540 lines — it ships
as an npm package and its dogfooding artifacts are consumer noise). This fork narrows that
on the `working` and `local/*` branches only (`.gitignore:40-44`), so five directories are
tracked. `next` keeps the blanket ignore byte-identical and carries **zero** `.planning`
entries, so none of this can reach a contribution branch.

| Folder | Holds | Filename | Staleness means |
|---|---|---|---|
| `reference/` | How a thing works. Consulted repeatedly. | plain, undated | **a bug** — fix or re-verify |
| `research/` | A measurement taken on a date against a version. | `YYYY-MM-DD-<slug>.md` | **expected** — each states its own version |
| `runbooks/` | Do these steps, in this order. | plain, undated | **a bug** — the steps are wrong |
| `seeds/` | A proposal awaiting a decision, with a trigger condition. | **`SEED-NNN-<slug>.md`** | n/a — it hasn't happened yet |
| `todos/pending/` | An actionable work item with a severity. | `YYYY-MM-DD-<slug>.md` | n/a — close it or it's still true |

Start here for procedure: **`.planning/runbooks/fork-install-and-update.md`** — how to
build, install, and update from this fork, and why `/gsd-update` must never be run.

**The distinction that matters:** `reference/` claims to be true *now*, `research/` claims
only to have been true *on its stated date against its stated version*. Never promote a
research doc to reference by moving it — re-verify it first, or the date-stamped caveat is
silently dropped.

### Rules that bite

- **Seeds have a machine contract; hand-writing one gets it wrong.** Use
  `/gsd-capture --seed`. Filename must be `SEED-{zero-padded}-{slug}.md` and frontmatter
  must be `id, status, planted, planted_during, trigger_when, scope` (`plant-seed.md:65-81`).
  Get it wrong and failures are *partial*, which is worse than loud: `gsd-tools list-seeds`
  still lists the file but renders blank columns for every key it could not find, and
  `--enrich` cannot target it at all because it greps `SEED-[0-9]+` (`plant-seed.md:26`).
  `src/audit.cts:788` additionally skips anything not matching `SEED-*.md`, and
  `gsd-core/workflows/explore.md:202` documents `{slug}.md`, which is simply wrong.
- **`reference/gsd-config-schema.md` is generated — never hand-edit.** Regenerate from this
  repo root: `node ~/.claude/scripts/gen-gsd-config-schema.cjs` (writes to the cwd's
  `.planning/reference/`; reads `~/.claude/gsd-core` unless `GSD_HOME` points here). Diff
  before committing.
- **`reference/gsd-knowledge-capability-reference.md` is not mechanically regenerable** —
  claims are file:line-cited against a specific commit. The intel trace found its §6 was
  wrong *when written*, not merely stale, so re-verify rather than bumping the header.
- **Cross-link by in-repo path, in both directions.** A research doc names the todo or seed
  it feeds; that todo or seed names the research doc. An unlinked investigation is a
  terminal artifact nobody finds again.
- **Never copy any of this into this repo's `.claude/`** — gitignored at `.gitignore:12`,
  so copies there are unversioned and drift silently. That has already happened once.

### Deliberately still ignored

`config.json`, `codebase/`, `reports/`, `HANDOFF.json`, `.continue-here.md` — all
regenerable or machine-local. Only material worth git history is tracked.

What lives in `~/.claude` instead is strictly what is bound to the *installed* GSD tree:
`scripts/gsd-local-patches-*.diff`, `gsd-pristine/` (the 1.10.0 baseline), and
`runbooks/gsd-update-runbook.md`.

## Contributing — quick reference

Full process: `CONTRIBUTING.md`. Line-cited distillation with every hard gate:
**`.planning/reference/contributing-reference.md`** (tracked; read before opening a PR).

**Issue-first, no exceptions.** No code before a maintainer labels the issue:
`confirmed-bug` (fix) / `approved-enhancement` / `approved-feature`. PRs without a
properly-labeled linked issue are closed automatically.

**Branch → PR:**
```bash
git checkout next && git pull --ff-only origin next
git checkout -b fix/NNN-slug        # or feat/, chore/, docs/, refactor/, test/, perf/, ci/, revert/
# ... commit, push to fork ...
gh pr create --base next --repo open-gsd/gsd-core
```
Target `next` for everything except `fix/critical-NNN-*` (prod emergencies → `main`).

**Non-negotiable per PR:** one concern only · correct PR template (Fix/Enhancement/
Feature) · `Closes #N` in the body · no draft PRs · changeset via
`npm run changeset -- --type <T> --pr <N>` if touching `bin/`, `gsd-core/`, `src/`,
`agents/`, `commands/`, `hooks/`, `sdk/src/` · **never edit `CHANGELOG.md` directly**.

**AI-agent work** (`docs/contributor-standards.md` §150-236 — stricter than
CONTRIBUTING.md, and not summarized there):
- Read `CONTEXT.md` in full + relevant ADRs + the approved issue scope **before writing
  anything**. Cite `CONTEXT.md` `KEY.SUBKEY=value` predicates verbatim by ID — never
  paraphrase. Pull them with `node gsd-tools.cjs query context-predicates --class|--prefix|--contains`.
- **TDD is a merge gate** for any behavior-adding task: RED (failing test, own commit) →
  GREEN → REFACTOR, committed separately.
- Worktree isolation mandatory for agent-written code — never commit agent output
  straight to an already-open branch without review.
- Never edit `.claude/agents/` (install-sync output, silently overwritten) — always edit
  `agents/`. Re-run `bin/install.js` to re-sync if they've drifted.

## Local verification before every push

```bash
env -u GSD_AGENTS_DIR npm test          # env scrub is mandatory on this machine — see .planning/reference/contributing-reference.md §6
npm run lint:ci
GITHUB_BASE_REF=next node scripts/changeset/lint.cjs   # silently passes without the env var
```
