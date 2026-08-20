# GSD workstream-mode commit-path defect — research findings

**Written:** 2026-08-19
**Supersedes:** `/tmp/gsd-ship-patch-note.md` (2026-08-19). That note is correct on the
core defect but **wrong in three places**; corrections are marked ⚠ below. Read this
file instead.
**Installed GSD:** 1.10.0 (`gsd-core/VERSION`). Upstream latest: **1.11.0**.
**Verification basis:** gsd-core source read at file:line, plus live `gsd-tools` runs in
`~/gsd-workspaces/bedrock-access/bootstrap-terraform` (the only repo with a live
workstream) and the pristine 1.11.0 tarball extracted to `/tmp/gsd-1110/`.

---

## TL;DR

| # | Finding | Verdict | Action |
|---|---|---|---|
| 1 | GSD **writes** the workstream `STATE.md` but **commits** the flat one | **REAL BUG, systemic** | Patch the 4 workflows that already hold the path |
| 2 | `state.update` (`ship.md:488-489`) is workstream-aware | **NOT a second bug** — opposite of the prior note's fear | No action |
| 3 | ⚠ glab support is a **local patch**, not upstream | Prior note wrong | Do **not** "correct the memory" as the note said |
| 4 | ⚠ `init.phase-op` does **not** resolve the workstream without `--ws` | Prior note wrong | Fix is necessary but **not sufficient** |
| 5 | ⚠ Ship does **not** write into another worktree | Prior note overstated | Blast radius is branch-local |
| 6 | `:171` branch-push design mismatch | Not a bug | Do **not** patch (prior note correct) |
| 7 | `:58` verification gate | Correct behavior | Do **not** defeat (prior note correct) |
| 8 | 1.11.0 does not fix any of this | — | Upstream one bug report for the whole class |

---

## 1. THE DEFECT — a write/commit resolution mismatch inside one step

The prior note framed this as "a hardcoded literal where the correct value was in
scope." That is true but too narrow, and it led to the wrong scope. The accurate
framing:

> **Within a single workflow step, the write and the commit resolve the target path by
> two different mechanisms. The write is workstream-aware. The commit is a literal.**

### The write side is correct

`ship.md:488-489`:
```bash
gsd_run query state.update "Last Activity" "$(date +%Y-%m-%d)"
gsd_run query state.update "Status" "Phase ${PHASE_NUMBER} shipped — PR #${PR_NUMBER}"
```

`cmdStateUpdate` (`gsd-core/bin/lib/state.cjs:316`) resolves:
```js
const statePath = planningPaths(cwd).state;
```
→ `planningPaths` → `planningDir(cwd, ws)` (`planning-workspace.cjs:100-121`), where an
omitted `ws` defaults to `process.env['GSD_WORKSTREAM']`, which the CLI entry point sets
from the resolution chain at `gsd-tools.cjs:3772-3777`.

**This resolves the workstream `STATE.md` correctly.** The prior note listed this as
"also check — not yet verified" and warned it might be "the same bug in a second place."
It is not. It is the half that works.

### The commit side is a literal

`ship.md:510` / `:513`:
```bash
gsd_run query commit "docs(...): ship phase ... — MR !${PR_NUMBER}" --files .planning/STATE.md
```

`cmdCommit` (`commands.cjs:811`) does `path.resolve(cwd, file)` then
`execGit(['add', file], { cwd })` — it stages exactly the literal it was handed. No
workstream resolution anywhere in the commit path.

### The two failure modes

`cmdCommit` skips explicitly-listed files that do not exist (`commands.cjs:812-817` —
deliberate, per #2014, so a temporarily-absent STATE.md is not staged as a deletion).
That split produces two distinct outcomes:

- **Flat `STATE.md` absent** (pure workstream project) → `nothing_to_commit`. Silent
  no-op. The workstream `STATE.md` is updated on disk and **never committed**. Planning
  state drifts out of git with no error. *Degraded.*
- **Both present** (parallel milestones — bootstrap-terraform's exact case) → the
  **other milestone's live `STATE.md`** is staged and committed under *this* milestone's
  ship message, and the real one stays uncommitted. *Destructive.*

There is a third shape at `execute-phase.md:990`, where the flat paths are used as a
**guard**:
```bash
if ! git diff --quiet .planning/ROADMAP.md .planning/STATE.md 2>/dev/null; then
```
In workstream mode this tests the wrong files, so the wave-tracking commit is skipped
entirely when the workstream files changed and the flat ones did not. Not a wrong
commit — **no commit at all.**

### ⚠ Correction — blast radius is branch-local, not cross-worktree

The prior note claimed ship would write "in a worktree that is not even the one that
owns it." **False.** `resolveMainWorktreeCwd` (`gsd-tools.cjs:3693`) returns `cwd`
unchanged the moment `cwd/.planning` exists:
```js
if (existsSync(path.join(cwd, '.planning'))) { return cwd; }
```
`~/gsd-workspaces/security-vpc/bootstrap-terraform/.planning/` exists, so gsd-tools stays
local to that worktree. The file wrongly committed is that worktree's **own** checked-out
flat `STATE.md`, onto its own branch. Still wrong; not cross-worktree corruption.

---

## 2. ⚠ THE FIX IS NECESSARY BUT NOT SUFFICIENT — resolution is session-scoped

The prior note asserted:

> "`init.phase-op` resolves the workstream path **without** `--ws` … Verified both ways —
> identical output with and without the flag."

**Empirically false.** Live run in `~/gsd-workspaces/bedrock-access/bootstrap-terraform`
(`workstream.list` reports `mode: "workstream"`, one workstream `bedrock-access`):

```
$ gsd-tools query init.phase-op --raw            # no --ws
  "state_path": ".../bootstrap-terraform/.planning/STATE.md"                        ← FLAT

$ gsd-tools query init.phase-op --ws bedrock-access --raw
  "state_path": ".../.planning/workstreams/bedrock-access/STATE.md"                 ← workstream
```

They are **not** identical. `mode: "workstream"` does not imply resolution.

### Why the prior note saw the opposite (both observations are real)

Resolution order is `--ws` flag > `GSD_WORKSTREAM` env > **stored active pointer**
(`active-workstream-store.cjs:276-300`). The stored pointer is **session-scoped**
whenever a session key is present — `pickActiveWorkstreamAdapter`
(`active-workstream-store.cjs:174-180`) keys on the first of:

```
GSD_SESSION_KEY, CODEX_THREAD_ID, CLAUDE_SESSION_ID, CLAUDE_CODE_SSE_PORT,
OPENCODE_SESSION_ID, GEMINI_SESSION_ID, CURSOR_SESSION_ID, WINDSURF_SESSION_ID,
TERM_SESSION_ID, WT_SESSION, TMUX_PANE, ZELLIJ_SESSION_NAME
```

The prior note's session had a pointer set (via `gsd-tools workstream set <name>`,
`workstream.cjs:343`); a Bash tool call in a different session does not inherit it. **Two
sessions, two answers, both correct.**

### The consequence that must not be missed

**The patch makes the writer and the committer *consistent*. It does not make them
*correct*.** With the pointer unset, `state.update` and the fixed commit both target the
flat `STATE.md` — the workstream `STATE.md` is then never updated *at all*, which is a
different failure, not a fixed one.

Pointer hygiene is a **separate, unfixed problem**, and it is worse than it looks:
`--ws` is accepted by only **3 of 40 workflows** — `new-milestone.md:27`,
`verify-work.md:42`, `plan-review-convergence.md:21`. **`ship.md`, `execute-phase.md`,
`execute-plan.md`, `discuss-phase.md`, and `plan-phase.md` have no `--ws` plumbing at
all.** For those, the only levers are the `GSD_WORKSTREAM` env var and a session-scoped
pointer that silently differs between your interactive session, a Bash subshell, and any
subagent.

**Operational rule until that is fixed:** set `GSD_WORKSTREAM=<name>` for every
lifecycle command in a workstream repo. It is the only lever stable across sessions and
subagents.

⚠ **A one-time `export` is not enough under an agent harness.** Claude Code's Bash tool
does not persist shell state between invocations — env vars set in one call are gone in
the next. Use one of:

- **per-command prefix** — `GSD_WORKSTREAM=<name> gsd_run query …` (works everywhere,
  including subagents);
- **repo-scoped** — a `direnv` `.envrc` or the project's shell profile, so every shell
  entering the tree inherits it;
- **interactive shell only** — a plain `export` is fine for a human terminal, and is what
  a hand-run `/gsd-ship` would pick up, but do **not** assume an agent-driven run
  inherited it.

---

## 3. SCOPE — this is systemic, not two lines in ship.md

The prior note found "two call sites; both in the `track_shipping` step." That is the
count *after* our local glab patch split upstream's single line in two. The real count
across `gsd-core/workflows/` is ~16, spanning every lifecycle event:

| Workflow | Line(s) | Hardcoded paths | Resolved path already in scope? |
|---|---|---|---|
| `execute-plan.md` | 507, 509 | `STATE.md`, `ROADMAP.md`, `REQUIREMENTS.md` | ✅✅ **already parsed at `:51`, then discarded** |
| `ship.md` | 510, 513 | `STATE.md` | ✅ `$INIT` at `:31`; add to parse list `:33` |
| `execute-phase.md` | 990 (guard), 991, 1450, 1507 | `STATE.md`, `ROADMAP.md`, `REQUIREMENTS.md` | ✅ `$INIT` at `:85`; add to parse list |
| `discuss-phase.md` | 484 | `STATE.md` | ✅ `$INIT` at `:119`; add to parse list `:123` |
| `discuss-phase-assumptions.md` | 587 | `STATE.md` | ❓ `init.discuss-phase-assumptions` |
| `import.md` | 240 | `ROADMAP.md` | ✅ `init.phase-op` |
| `plan-milestone-gaps.md` | 157 | `ROADMAP.md`, `REQUIREMENTS.md` | ✅ `init.phase-op` |
| `remove-phase.md` | 107 | `.planning/` (**whole tree**) | 🔴 see hazard below |
| `add-todo.md` | 156 | `STATE.md` | ❌ `init.todos` |
| `check-todos.md` | 163 | `STATE.md` | ❌ `init.todos` |
| `complete-milestone.md` | 493 | `STATE.md`, `ROADMAP.md`, `PROJECT.md`, `MILESTONES.md` | ❌ `init.complete-milestone` |
| `new-milestone.md` | 266, 583 | `STATE.md`, `ROADMAP.md`, `REQUIREMENTS.md`, `PROJECT.md` | ❌ (but accepts `--ws`) |
| `next.md` | 191 | `ROADMAP.md` | ❌ no init query |
| `ingest-docs.md` | 314 | `STATE.md` | ✅ `init.ingest-docs` |

### 🔴 `remove-phase.md:107` is a data-loss path, not an over-staging nit

```bash
gsd_run query commit "chore: remove phase {target} ({original-phase-name})" --files .planning/
```

Trace it through `cmdCommit`: `.planning/` is an explicit file, it exists, so
`execGit(['add', '.planning/'])` stages **the entire flat planning tree** — the other
milestone's live `STATE.md`, `HANDOFF.json`, every in-flight artifact — and the commit
pathspec (`commands.cjs:884-891`) then commits all of it under a `chore: remove phase N`
message. In a parallel-milestone repo that is a silent cross-milestone commit with a
message that actively misdescribes it.

It is **out of the recommended patch scope** only because fixing it needs a resolved
planning-directory field that `init.phase-op` does not expose (it has `planning_exists`,
a boolean, but no `planning_dir`). Adding that field is an upstream change, not a
workflow substitution. **Until then, do not run `/gsd-remove-phase` in a repo with two
live milestones.**

**`execute-plan.md` is the sharpest instance.** Its parse list at `:51` already reads
`state_path` out of the init bundle:

```
Extract from init JSON: `executor_model`, `commit_docs`, `sub_repos`, `phase_dir`,
`phase_number`, `plans`, `summaries`, `incomplete_plans`, `state_path`, `config_path`,
`response_language`.
```

`STATE_PATH` then appears **nowhere else in the file**, while `:509` commits
`.planning/STATE.md`. The value is pulled into scope and thrown away at the one place it
matters — no new query needed, a one-token substitution.

**Which init verbs expose `state_path`** (`init.cjs`, one per function):

| Verb | Line | Exposes `state_path` |
|---|---|---|
| `init.execute-phase` | 781 | ✅ |
| `init.plan-phase` | 899 | ✅ |
| `init.new-milestone` | 1050 | ✅ |
| `init.ingest-docs` | 1157 | ✅ |
| `init.resume` | 1189 | ✅ |
| `init.verify-work` | 1244 | ✅ |
| `init.phase-op` | 1579 | ✅ |
| `init.progress` | 2506 | ✅ |
| `init.todos`, `init.complete-milestone`, `init.manager` | — | ❌ |

**All eight expose `roadmap_path`, `requirements_path` and `config_path` alongside
`state_path`, on the same `planningDir(cwd)` base** — confirmed at `init.cjs:781-790`
(`init.execute-phase`), `:899-902` (`init.plan-phase`), `:1157-1163` (`init.ingest-docs`),
`:1244-1245` (`init.verify-work`), and live:

```
$ gsd-tools query init.execute-phase 1 --ws bedrock-access --raw
  "state_path":        ".../.planning/workstreams/bedrock-access/STATE.md"
  "roadmap_path":      ".../.planning/workstreams/bedrock-access/ROADMAP.md"
  "requirements_path": ".../.planning/workstreams/bedrock-access/REQUIREMENTS.md"
  "config_path":       ".../.planning/workstreams/bedrock-access/config.json"
```

This matters because the offending lines commit **multiple** paths.
`execute-phase.md:1450` commits `ROADMAP.md` + `STATE.md` + `REQUIREMENTS.md` +
`{phase_dir}/*-VERIFICATION.md`, and `execute-plan.md:509` commits four. Since every
component resolves off the same bundle (`phase_dir` included), those lines stay **pure
substitutions** — no line ends up half-resolved. A half-resolved line would be worse than
no fix at all, because it reads as fixed.

**`state.load` does NOT** expose these — only `debug_dir` (`state.cjs:194`) — so a
workflow holding only `$CONFIG` has nothing to substitute.

**⚠ Todos are workstream-scoped too.** `.planning/todos/{pending,completed}` are built on
`planningDir(cwd)` (`commands.cjs:1554-1555`, `init.cjs:1616`), not `planningRoot`. So
`execute-phase.md:1507` is wrong in **all three** of its paths, not just `STATE.md`. And
`init.todos` *does* expose `pending_dir` / `completed_dir` (`init.cjs:1662-1663`) — but
not `state_path`. That makes `add-todo.md:156` and `check-todos.md:163` the exact
half-resolvable case above: todo dirs fixable from the bundle in scope, `STATE.md` not.
**That is the reason they are out of patch scope** — not merely that they are
low-traffic.

---

## 4. THE FIX

### Mechanically sound

- `state_path` is **absolute** (`init.cjs:1578` comment: *"#2376: absolute — see comment
  on phase_dir above"*), matching `phase_dir`, which this workflow already uses. Absolute
  is the established convention here, not a deviation.
- `cmdCommit` handles absolute paths: `path.resolve(cwd, file)` for the existence check
  (`commands.cjs:811`), then `git add <file>` with `cwd` set (`commands.cjs:836`). Git
  accepts absolute paths inside the repo, and the commit pathspec reuses the same strings
  (`commands.cjs:884-891`).
- **Not gitignored** — verified, because a failed `git add` would abort the whole commit
  with `staging_failed` (`commands.cjs:856-880`), turning today's silent wrong commit
  into a hard ship-time failure. `cmdCommit` only early-returns on `isGitIgnored(cwd,
  '.planning')` — the *parent* — so an ignored subtree would not be caught:
  ```
  $ git check-ignore -v .planning/workstreams/bedrock-access/STATE.md   → exit 1 (not ignored)
  $ git check-ignore -v .planning/workstreams/                          → exit 1 (not ignored)   [security-vpc]
  ```
  The fix is a fix, not a regression.

### The edit (ship.md)

Add `state_path` to the parse list at `ship.md:33`, binding `STATE_PATH`, then:

```bash
gsd_run query commit "docs(${padded_phase}): ship phase ${PHASE_NUMBER} — MR !${PR_NUMBER}" \
  --files "${STATE_PATH}"
```

Both `:510` and `:513`. **Never one without the other** — a partial fix on a
data-corruption path fails in the bug's direction.

### Recommended scope

Patch the **four lifecycle workflows where the resolved path is already in scope** and
the substitution is a pure one-liner with no new query: `ship.md`, `execute-phase.md`,
`execute-plan.md`, `discuss-phase.md`. These are the events that actually fire in a
milestone. `execute-phase.md:990`'s `git diff --quiet` guard must be substituted too, or
the fixed commit below it is never reached.

Leave the rest (`add-todo`, `check-todos`, `complete-milestone`, `next`,
`discuss-phase-assumptions`) — each needs a **new** `gsd_run` call, which is real
maintenance debt on every GSD bump for workflows that touch workstream state rarely.
Carry them in the upstream report instead.

---

## 5. ⚠ WITHDRAWN — the prior note's finding #3 is wrong

The prior note said the `gh`-only claim was "FALSE — already fixed upstream" and
instructed: *"Correct the stale memory."* **Do not do this.**

`/gsd-ship` handles GitLab **only because of our own local patch.** From
`notes/gsd-glab-port.md`:

> **STATUS 2026-08-17: IMPLEMENTED as a local patch.** All 14 call sites edited in
> `~/.claude` against installed 1.10.0 …
> **Upstream is closed to this.** open-gsd/gsd-core#2138 asked for glab support;
> maintainer reply 2026-07-12: *"gitlab will not be added, it is not supported by us. we
> use GitHub exclusively."* Permanent local patch — do not re-propose.

Confirmed against the pristine tarball: **1.11.0 `ship.md` contains no `glab`**, and its
forge check is still `which gh && gh auth status`. The lines the prior note cited as
evidence of upstream support (`:90-91`, `:98`, `:350-354`, `:373-377`, `:505-508`) are
*our patch's added lines*, visible in `scripts/gsd-local-patches-1.10.0.diff:1097+`.

**The memory was right when written and is now conditionally superseded.** The correct
form is: *"`/gsd-ship` works against self-hosted GitLab **while the local patch set is
applied**; gsd-core is replaced wholesale by every update, so verify the patch is live
before trusting it."* Recording it as "upstream fixed it" would send a future session to
ship through a gh-only workflow after the next bump.

---

## 6. Findings the prior note got right — no change

**`ship.md:171` branch push (design mismatch, do not patch).** `/gsd-ship` assumes the
phase branch *is* the MR. bootstrap-terraform deliberately keeps `.planning/workstreams/`
off `origin/main`, so the branch carries 22 files where the MR should carry 1; shipping
as-is drags `.planning/HANDOFF.json` in, and `**/*.json` is in `.tofu_change_globs`
(`.gitlab-ci.yml`), losing the ~9s docs-only skip path. Adding curation logic would be a
fork, not a fix. The manual path is four commands.

**`ship.md:58` verification gate (correct behavior, do not defeat).** `/gsd-ship 81`
halts because phase 81 genuinely is half done — `81-02` has not executed. `/gsd-ship`
ships *phases*; MR !1098 ships a *wave*. Patching around this is the "disabling a check
that caught something" band-aid tell from `CLAUDE.md`.

---

## 7. Upstream status — 1.11.0 does not fix it

Verified against `/tmp/gsd-1110/package/gsd-core/workflows/ship.md`:

- `:483` — still `gsd_run query commit "…" --files .planning/STATE.md` (one site;
  upstream never split it, our glab patch did).
- `:35` — parse list still `phase_found, phase_dir, phase_number, phase_name,
  padded_phase, commit_docs`. No `state_path`.
- The full ~16-site hardcode class is intact across 1.11.0's workflows.

**File one upstream bug for the whole class**, not for ship.md alone. **Lead it with
`execute-plan.md`** — a workflow that parses `state_path` at `:51` and then hardcodes
`.planning/STATE.md` at `:509` is self-evidently a defect and needs no workstream-mode
exposition to land. `ship.md` is the weaker opening because its fix requires adding a
field to the parse list first. It is
general-purpose, needs no new flag or config, and the resolved paths already exist on the
init bundles. A local patch here is maintenance debt on every bump.

### Upgrade hazard to record now

1.11.0 rewrote the `ship:pre` gate region (roughly `:94-127`, "Security ship gate" →
"Capability ship gates (generic dispatch)"). **One of our glab hunks lands in that
region and will conflict at the 1.10.0 → 1.11.0 bump.** Budget for a manual rebase of the
`ship.md` stanza.

---

## 8. Patch mechanics — the trap

`scripts/gsd-local-patches-1.10.0.diff` **already contains one**
`--- a/gsd-core/workflows/ship.md` stanza (line 1097). **Do not append a second stanza
for the same file pair** — `patch -p1` will not reapply it cleanly.

Correct procedure:
1. Edit the installed `~/.claude/gsd-core/workflows/ship.md`.
2. **Regenerate** the ship.md section by re-diffing
   `gsd-pristine/gsd-core/workflows/ship.md` against the edited installed file, so all
   hunks live under a single file header.
3. Run `gsd-core/bin/verify-reapply-patches.cjs` — confirm `patch -p1` from pristine
   reproduces the installed file byte-identically (the same gate `gsd-glab-port.md`
   records as already passing).
4. Register in `runbooks/gsd-update-runbook.md` (the patch inventory starts at `:124`).
5. Any newly-patched file (`execute-phase.md`, `execute-plan.md`, `discuss-phase.md`)
   needs a **pristine baseline seeded into `gsd-pristine/`** first, or step 3 has nothing
   to diff against.

---

## Current exposure in your repos

`bedrock-access` is the only live workstream:
`~/gsd-workspaces/bedrock-access/bootstrap-terraform/.planning/workstreams/bedrock-access/`
— `has_state: true`, `phase_count: 0`, `status: "Not started"`, and the whole subtree is
**untracked** (`git status` → `?? .planning/workstreams/`). No lifecycle event has run
there yet, so the bug has not fired — **it fires on the first `/gsd-execute-phase`.**

`security-vpc` is claimed for workstream `tenant-vpc-reach` in
`.planning/PHASE-LEDGER.md:148` but the directory does not exist in that worktree yet
(the checkout is on `docs/81-01-reanchor-prd`). It becomes exposed the moment the
workstream is created.

---

## Do not do

- **Do not** patch the `:58` verification gate or add a `--force`/`--skip-verify` bypass.
- **Do not** add branch-curation to `ship.md`. Fork, not fix.
- **Do not** fix `:510` without `:513`, or substitute `execute-phase.md:991` without also
  substituting the `:990` guard above it.
- **Do not** append a second `ship.md` stanza to the 1.10.0 diff — regenerate it.
- **Do not** record "/gsd-ship supports GitLab" unconditionally. It is patch-dependent.
- **Do not** run `/gsd-remove-phase` in a repo with two live milestones — `:107` stages
  the entire flat `.planning/` tree under a "remove phase N" message.
- **Do not** rely on a one-time `export GSD_WORKSTREAM` for agent-driven runs; Bash-tool
  shell state does not persist between invocations.
