---
created: 2026-08-20T03:42:57.000Z
title: Fix the inert glab forge port and migrate it from GSD 1.10.0 to 1.11.0
area: tooling
severity: blocker
files:
  - gsd-core/workflows/ship.md:90 (auth — stable across versions)
  - gsd-core/workflows/ship.md:364 (was :338 at 1.10.0 — gh pr create)
  - gsd-core/workflows/ship.md:461 (was :435 at 1.10.0 — gh pr edit --add-reviewer)
  - gsd-core/workflows/ship.md:497 (NEW at 1.11.0 — gh pr view --json, unported)
  - gsd-core/workflows/ship.md:~479-490 (ship-note [ci skip] trailer — patched but undocumented in the note)
  - gsd-core/workflows/inbox.md:33,40,57,146,161,310,314,327,332 (all 9 byte-stable)
  - gsd-core/workflows/pr-branch.md:301 (byte-stable)
  - gsd-core/references/checkpoints.md:414 (byte-stable)
  - ~/.claude/scripts/gsd-local-patches-1.10.0.diff (the patch to re-author)
  - ~/.claude/gsd-pristine/gsd-core/ (1.10.0 baseline the patch was authored against)
  - .planning/research/2026-08-17-glab-forge-port-map.md (the source port map)
  - .planning/runbooks/porting-local-patches-assets/glab/fence-derive.sh (inertness proof — $FORGE never reaches its guards)
  - .planning/runbooks/porting-local-patches-assets/glab/fence-create-pr.sh (inertness proof — the create-pr fence)
  - .planning/runbooks/porting-local-patches-assets/glab/stubbin/gh (stub used to prove which binary is actually invoked)
  - .planning/runbooks/porting-local-patches-assets/glab/stubbin/glab (stub used to prove which binary is actually invoked)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.9 and §4c — this todo's row in the port campaign)
---

## Problem

**Two things in one item**, and the second is why this is `blocker`:

1. A **local feature migration** — re-author the 1.10.0 patch against 1.11.0. Unlike the
   other todos in this list, this half is not an upstream defect.
2. A **live correctness defect in the port itself** (Finding 3): `$FORGE` never reaches
   any of its guards, so the currently-installed port silently takes the GitHub branch
   every time. It is not merely stale — as installed, it does nothing on GitLab.

Originally filed `major` on the assumption this was version drift only; raised to
`blocker` once Finding 3 was measured. Same silent-fallthrough class as the
`pause-work` dead-gate todo.

GSD's forge-facing workflows are GitHub-only: they shell out to `gh` with no `glab`
path. On a GitLab remote, `/gsd-ship` cannot open an MR and `/gsd-inbox` cannot triage.
A full `gh` → `glab` port was researched, implemented, and verified as a local patch
against **GSD 1.10.0** (see `.planning/research/2026-08-17-glab-forge-port-map.md`, verified 2026-08-17
against context7 `/gitlab_gitlab-org/cli` and the installed `glab 1.107.0` binary).

**Upstream is permanently closed to this.** `open-gsd/gsd-core#2138` asked for glab
support; maintainer reply 2026-07-12: *"gitlab will not be added, it is not supported
by us. we use GitHub exclusively."* This can only ever live locally. Do not re-propose.

The patch currently lives at `~/.claude/scripts/gsd-local-patches-1.10.0.diff` (item 14
in `~/.claude/runbooks/gsd-update-runbook.md` (stays in dotclaude — it patches the installed tree)), applied to an installed **1.10.0** tree. This repo's
`next` is at **1.11.0**. The patch has drifted and has a real coverage hole.

## Verification (this repo, 2026-08-20)

Every claim below was checked against tags in this checkout and against the on-disk
pristine baseline — not inferred from the note.

**Baseline is genuinely 1.10.0.** `~/.claude/gsd-pristine/gsd-core/workflows/ship.md`
is byte-identical to `git show v1.10.0:gsd-core/workflows/ship.md` (550 lines both)
except for the install-time `/gsd:` → `/gsd-` command-prefix transform. The installed
patched copy is 607 lines (+57 = the applied patch).

### Line drift 1.10.0 → 1.11.0

| File | 1.10.0 | 1.11.0 | Drift |
|---|---|---|---|
| `ship.md` auth | :90 | :90 | stable |
| `ship.md` `gh pr create` | :338 | :364 | **+26** |
| `ship.md` `gh pr edit --add-reviewer` | :435 | :461 | **+26** |
| `ship.md` `gh pr view --json` | *absent* | **:497** | **new site** |
| `inbox.md` (all 9 sites) | :33…:332 | :33…:332 | stable |
| `pr-branch.md` | :147/:187/:301 | :147/:187/:301 | stable |
| `checkpoints.md` | :414 | :414 | stable |

**So the migration is one file's worth of rebase.** `ship.md` is the only file that
moved.

### Dry-run result (measured, not estimated)

Extracted the four v1.11.0 files to a scratch tree and ran the 1.10.0 patch against
them (`patch -p1 --dry-run --forward`):

| File | Result |
|---|---|
| `references/checkpoints.md` | **clean** |
| `workflows/inbox.md` | **clean** (all 6 hunks) |
| `workflows/pr-branch.md` | applies, but **with fuzz 2** — hand-verify, do not trust a fuzzy apply |
| `workflows/ship.md` | 3 of 4 hunks apply; **1 fails** |

`ship.md` detail:

```
Hunk #1 succeeded at 85 with fuzz 2.       ← auth
Hunk #2 succeeded at 373 (offset 26 lines). ← mr create
Hunk #3 succeeded at 493 (offset 26 lines). ← mr update --reviewer
Hunk #4 failed at 521.                      ← ship-note [ci skip] trailer
```

**The only hunk that fails is the one the note never documents (Finding 2), and it
fails because of the new call site (Finding 1)** — `68a199cf` inserted the `gh pr view`
poll block into exactly the ship-note region hunk #4 patches. The two findings are the
same collision seen from opposite sides.

Hunk #1's `fuzz 2` is minor context drift; cause not investigated — re-verify that hunk
by hand rather than trusting a fuzzy apply.

Practical consequence: **~90% of the migration is a clean replay.** The real work is
one hunk plus the `:497` decision below.

### Finding 1 — a new, unported `gh` call site landed in 1.11.0

`ship.md:497` (v1.11.0):

```bash
PR_STATE=$(gh pr view ${PR_NUMBER} --json headRefOid,mergeStateStatus,statusCheckRollup,reviewDecision -q '…')
```

Introduced by `68a199cf fix(#2783): address wedged PRs in ship note protocol (#2818)`.
Confirmed **not** an ancestor of `v1.10.0` (`git merge-base --is-ancestor 68a199cf
v1.10.0` → false), and confirmed absent from the pristine 1.10.0 `ship.md`. So it is
genuinely new in the 1.10.0→1.11.0 window (338 commits, per
`git rev-list --count v1.10.0..v1.11.0` — note the pause handoff's "46 commits" was the
local `2b9713a6..7cf6a079` pull span, not the tag range).

This is the hardest site in the whole port, because it polls four GitHub-specific
fields in one call:

| Field | GitLab equivalent | Status |
|---|---|---|
| `headRefOid` | `sha` / `diff_refs.head_sha` on the MR object | needs confirming |
| `mergeStateStatus` | **unresolved** — candidate is `detailed_merge_status` | **unverified, needs a spike** |
| `statusCheckRollup` | `head_pipeline.status`, or `glab ci status -b <branch> -F json` | per the note's mapping table |
| `reviewDecision` | `glab mr approvers <id> -F json` | per the note's mapping table |

`glab mr view -F json --jq` returns the raw GitLab REST MR object (confirmed via
context7 `/gitlab_gitlab-org/cli`, `docs/source/mr/view.md` — `-F/--output text|json`
plus `--jq`), so whatever field GitLab exposes is reachable. **But which field is the
true analog of GitHub's `mergeStateStatus` (`BLOCKED`/`CLEAN`/…) is not established** —
context7 does not document `detailed_merge_status` for the CLI, since glab passes the
API object through untouched. Resolve with a spike against a real GitLab MR before
writing the branch; do not assume.

Also note the surrounding logic is GitHub-semantics all the way down: it detects a PR
wedged `BLOCKED` with zero checks caused by a `[ci skip]` trailer. The existing patch
already makes the *trailer* forge-aware (see Finding 2) — so on GitLab the wedge this
block exists to repair should not occur, and the right port may be to **guard the whole
block behind `[ "$FORGE" != gitlab ]`** rather than translate it field-by-field. Decide
that explicitly; it is the cheaper and probably more correct answer.

### Finding 2 — the note under-documents its own implementation

The note's inventory lists `ship.md` as **3** sites (:90, :338, :435) and totals "14
call sites". The actual patch contains **4** `ship.md` hunks:

```
@@ -85,11  +85,23  @@   → auth
@@ -335,14 +347,37 @@   → mr create
@@ -432,7  +467,14 @@   → mr update --reviewer
@@ -453,8  +495,23 @@   → ship-note [ci skip] trailer   ← in NO table in the note
```

The fourth hunk drops the `[ci skip]` trailer from the ship-note commit when
`$FORGE` is `gitlab`, because GitLab evaluates the MR merge check against the **HEAD
commit's** pipeline, so a `[ci skip]` ship-note pushed after MR creation leaves the MR
with a `skipped` head pipeline. That rationale exists only inside the diff.

**Consequence:** re-deriving the port from `gsd-glab-port.md` alone would silently drop
this change. Work from the diff, and treat the note as commentary.

Hunk counts for the other files (for rebase planning): `inbox.md` 6, `pr-branch.md` 1
(`@@ -298,7`), `checkpoints.md` 1 (`@@ -412,6`).

## Coverage audit — is the whole `gh` surface actually covered?

Swept at v1.11.0 with word-boundary greps across **every shipped runtime dir**
(`gsd-core/`, `hooks/`, `agents/`, `skills/`, `commands/`, `bin/`, `templates/`, `src/`),
for three separate axes: `gh <subcommand>` invocations, `api.github.com`/`github.com[:/]`
host coupling, and `GH_TOKEN`/`GITHUB_TOKEN`/`GH_HOST`.

**Verdict: file coverage is complete. Scope coverage is not.**

| Location | `gh` sites | Port status |
|---|---|---|
| `workflows/inbox.md` | 9 | covered |
| `workflows/ship.md` | 4 | 3 covered, **`:497` not** (Finding 1) |
| `workflows/pr-branch.md` | `:187`, `:301` (+`:147` prose) | `:301` covered; `:187` deferred |
| `references/checkpoints.md` | `:414` | covered (doc table row) |
| `workflows/forensics.md` | `:259`, `:265` | correctly out of scope — targets `open-gsd/gsd-core` |
| `src/commands.cts` + built `commands.cjs` | `github.com[:/]` slug regex `:1703` | deferred |

Cleared (no forge coupling found):

- **`hooks/`, `agents/`, `skills/`, `commands/`, `templates/`, `bin/` — zero `gh`
  invocations.** The note's "thin wrappers carry none" claim holds at 1.11.0.
- **Zero `GH_TOKEN`/`GITHUB_TOKEN`/`GH_HOST`** anywhere in shipped runtime — no
  token-env coupling to port.
- **`.github/` hits are the Copilot host config dir**, not forge coupling. Copilot uses
  `.github/` the way Claude uses `.claude/` (`runtime-name-policy.cts:137`,
  `runtime-artifact-conversion.cts:339-345`, `init.cts:3726`). Unrelated.
- **`capability-trust` host allowlist is generic** (`hostMatchesAllowlist(host, list)`,
  `src/capability-trust.cts:1019`) — `github.com` is only the doc-comment example, not a
  hardcoded gate. Capability *sources* are a different subsystem from forge operations.
- Remaining `github.com` hits across `gsd-core/` and `src/` are doc-comment citations
  and links to other projects (cline, hermes, thinking-partner, claude-code). Not coupling.

> **Validated 2026-08-20 — inertness MEASURED, not just reasoned.** A stubbed re-execution of the
> verbatim fences (`glab auth status` exit 0, `gh auth status` exit 1 — a GitLab-only remote)
> confirmed `create_pr` still dispatches to **`gh`**: `STUB: gh pr create was invoked`, with
> `$FORGE` empty at guard time.
>
> Stronger than the fence argument: **all 4 `ship.md` guards sit in a different `<step>` than the
> derivation**, not merely a different fence — steps are GSD's atomic execution unit. Same for 7 of
> 8 `inbox.md` guards; only `inbox.md:53` shares a step. Corroborated in-tree by
> `execute-phase.md:544` (*"a bare cd does not persist across separate tool invocations"*). No
> ambient collision: `FORGE` is unset in env, all shell rc files and `settings.json`, and no
> `CLAUDE_ENV_FILE`/`BASH_ENV` mechanism exists in the hooks.
>
> **Calibration on "every time":** proven is the mechanism and the consequence under verbatim
> re-execution. Workflows are executed by a model, not an interpreter, and the derivation fence
> echoes `forge=gitlab` into that model's context — so a model *could* inline the literal at a
> guard, most plausibly at `inbox.md:53`. The defect is therefore model-dependent and fail-open,
> not a certainty. Same root cause, same fix; phrase it as "under the shell-state model GSD's own
> docs describe" rather than an unconditional universal.
>
> **Fix refined:** prefer a `gsd_run query forge.detect`-shaped re-derivation per guard-bearing
> fence, matching how every other cross-fence value already works
> (`BASE_BRANCH=$(gsd_run query git.base-branch)`, `:46`, is the direct analogue). **Argue against
> caching in `.planning/config.json`** — the derivation is deliberately probe-authoritative (its own
> comment: *do NOT infer the forge from the hostname*) because remote/auth state changes between
> runs, and a durable settings file reintroduces that staleness. Keep fail-closed as an independent
> second layer regardless.

### Finding 3 — `$FORGE` never reaches its guards: the installed port is inert on GitLab

**This is a live defect in the currently-installed patched 1.10.0 tree, not a latent
risk in the migration.** It is the real coverage gap, and it is a design weakness in the
port rather than version drift.

Measured against the live `~/.claude/gsd-core/workflows/ship.md` (patched 1.10.0):

| | Line | Enclosing fence |
|---|---|---|
| `FORGE_HOST=` derivation | :94 | **outside any fence** |
| `FORGE=""` derivation | :96 | **outside any fence** |
| guard `[ "$FORGE" = gitlab ]` | :350 | 343–366 |
| guard | :373 | 372–379 |
| guard | :470 | 469–478 |
| guard | :508 | 507–516 |

**Zero of the four guards share a scope with the derivation.** GSD workflows execute as
a sequence of separate Bash tool calls, and shell state (env vars, functions) does not
persist between them — so `$FORGE` is empty at all four guard sites, every guard
evaluates false, and control takes the GitHub branch each time. The port is inert.

Confidence: high, from static structure. **Not** confirmed by running `/gsd-ship`
against a real GitLab remote — do that before investing in the migration, since it
determines whether this is a rewrite or a rebase.

Note what was and was not previously verified: the note records *"Reapply verified:
`patch -p1` from pristine reproduces all four files byte-identically."* That verifies
**patch mechanics**, not **runtime behaviour**. No end-to-end GitLab run is recorded
anywhere. That gap is how a port can be byte-perfect and still do nothing.

`$FORGE` is not a GSD config key and not a `gsd_run query` output. The patch derives it
inline with a bash-local:

```bash
FORGE_HOST=$(git remote get-url origin 2>/dev/null | …)
FORGE=""
gh   auth status --hostname "$FORGE_HOST" >/dev/null 2>&1 && FORGE=github
glab auth status --hostname "$FORGE_HOST" >/dev/null 2>&1 && FORGE=gitlab
```

…and does so **twice** (once in `ship.md`, once in `inbox.md`). But every guard is
`if [ "$FORGE" = gitlab ]`, and **each markdown bash fence is a separate execution** —
a variable set in one fence does not exist in the next.

Measured fence-to-site mapping for `ship.md` at v1.11.0:

| `gh` site | Enclosing fence |
|---|---|
| `:90` (auth) | *outside any fence* |
| `:364` (`pr create`) | 357–368 |
| `:461` (`pr edit --reviewer`) | 460–462 |
| `:497` (`pr view --json`) | 482–519 |

Four sites, four distinct scopes. Wherever `$FORGE` is unset, `[ "$FORGE" = gitlab ]`
is false and control **falls through to the GitHub branch silently** — the same
silent-dead-gate failure class already captured in the `pause-work` todo.

**Migration is the moment to fix this, not just rebase around it.** Options, cheapest
first:

1. Re-derive `FORGE` at the top of every fence that branches on it (mechanical, verbose,
   costs 2 auth probes per fence).
2. Persist it once — write `forge` into `.planning/config.json` and read it via
   `gsd_run query`, matching how every other cross-fence value in GSD travels.
3. Fail closed: `case "$FORGE" in github|gitlab) ;; *) echo "forge undetermined"; exit 1 ;; esac`
   at each branch point, so an unset `$FORGE` stops rather than silently doing GitHub.

(2)+(3) together is the robust answer; (1) alone reproduces the fail-open risk at every
new site anyone adds later.

### Finding 4 — deploy-config detection is GitHub-only (cosmetic)

`src/docs.cts:177` lists `.github/workflows/deploy.yml|.yaml` in `deployFiles` with no
`.gitlab-ci.yml` counterpart, so a GitLab project whose deploy runs from GitLab CI
reports `has_deploy_config: false`. Cosmetic — affects a docs heuristic only, no
workflow branches on it. Note it, don't block on it.

## External artifacts this todo depends on

**Two** artifacts live outside this repo, in the `faffi/dotclaude` repo (`~/.claude`) —
both bound to the *installed* GSD tree, which is why they stay there rather than moving
in here. Locate by **filename**, not by path. Everything else is in this repo.

| Artifact | Path at time of writing | Why it is needed |
|---|---|---|
| `gsd-local-patches-1.10.0.diff` | `~/.claude/scripts/` | **The port itself.** Source of truth — the note under-documents it (Finding 2). Without this the work restarts from scratch. |
| `gsd-pristine/gsd-core/` (16 files) | `~/.claude/gsd-pristine/` | The 1.10.0 baseline the patch was authored against; every provenance diff resolves here. Reproducible via `git show v1.10.0:<path>` if lost. |
| `2026-08-17-glab-forge-port-map.md` | `.planning/research/` (in this repo) | Provenance only — flag reference and trap list. Known to under-document the patch; **work from the diff, not this.** |

Only the patch is genuinely irreplaceable. The baseline regenerates from this repo's own
`v1.10.0` tag, and the port map's durable content is already reproduced in this todo.

Once the work lands as `local/glab-forge-port` in this repo, all three become historical
and this section can be deleted.

## Recommended approach

**Move it from the patch-file mechanism to a `local/<slug>` branch.**

```bash
git checkout -b local/glab-forge-port next
```

The note's stated durability options were "land upstream (preferred) or register as a
local patch" — but it was written before this repo's `next`/`working`/`local/<slug>`
branch model existed, and upstream is permanently closed. A `local/*` branch survives
`/gsd-update` **by construction** (merge `next` forward, resolve once), whereas the
patch file needs a manual reapply-and-verify on every version bump and is silently
deleted if `bin/install.js` wipe-and-replaces `gsd-core/` first. That is a strictly
better home than what the note contemplated.

Ordering:

1. Branch off `next`, apply the patch — `checkpoints.md`, `inbox.md`, `pr-branch.md`
   and `ship.md` hunks 2–3 land automatically (measured above).
2. Hand-verify `ship.md` hunk #1 (applied with fuzz 2) and hand-write hunk #4, whose
   ship-note region was rewritten by `68a199cf`.
3. Spike `ship.md:497`: decide guard-behind-`$FORGE` vs. field-by-field translation,
   and resolve the `mergeStateStatus` mapping empirically first. Do this **with** step 2
   — hunk #4 and `:497` touch adjacent lines and should be reasoned about together.
   Note the guard-behind-`$FORGE` option is only sound once Finding 3 is fixed: `:497`
   sits in fence 482–519, which never derives `$FORGE`, so a naive guard fails open.
4. Fix Finding 3 (`$FORGE` fence scoping + fail-closed) as part of this migration.
   It is the difference between a port that works and a port that silently no-ops.
4. Retire `~/.claude/scripts/gsd-local-patches-1.10.0.diff` item 14 and the
   `gsd-pristine/` seeds for these 4 files once the branch is the source of truth —
   two mechanisms for one change is how the note's own drift happened.

### Traps to carry forward (from the note, still valid)

- **No `--body-file`.** `glab mr create -d` takes a string; `-d -` opens an editor
  (fatal non-interactively). Read the temp file into the flag.
- **`--reviewer` replaces, `gh --add-reviewer` appends.** Prefix `+` to add. A literal
  port silently drops existing reviewers. Same for `-a/--assignee`.
- **`-H/--head` is not `gh`'s `--head`.** It selects another head *repository*; the
  branch flag is `-s/--source-branch`. A literal port yields a wrong-repo MR.
- **`-F` means three different things.** `glab issue list` needs `-O json` (`-F` there
  is `--output-format details|ids|urls`); `mr list`/`mr view`/`repo view`/`ci *` use
  `-F json`; `glab api` uses `-F` for typed fields.
- **`--squash-before-merge` on create, not `--squash`.** On `mr create`, `-s` is
  `--source-branch`; on `mr merge`, `-s` is `--squash`. Same letter, opposite meaning.
- **`glab issue close` has no `--comment`** — two calls (`issue note` then `close`).
  `glab mr note create <id> -m` is EXPERIMENTAL in 1.107.0; stable fallback is
  `glab api --method POST projects/:fullpath/merge_requests/<iid>/notes`.

## Out of scope

- `gsd-core/workflows/forensics.md:259,:265` — both hard-target `open-gsd/gsd-core` for
  upstream bug reports. GitHub regardless of the operator's forge. Leave as-is.
- `src/commands.cts` host-aware `remote_slug` (GitHub-only regex, yields `null` for
  GitLab so `pr-branch.md:187` silently skips). Correct-but-unhelpful, not blocking.
  If ever done, edit `src/commands.cts` — never `gsd-core/bin/lib/commands.cjs`, which
  is gitignored `tsc` output.

## Trigger

Not blocking today: `~/.claude` still runs patched 1.10.0. This becomes blocking the
moment `/gsd-update` moves the installed tree to 1.11.0 — at which point `gsd-core/` is
wipe-and-replaced and the port disappears without warning.
