# GSD Lifecycle Events

<purpose>
Reference documentation for GSD's hook-based lifecycle events — which points fire on which
workflows, what capabilities register hooks at each point, and how the dispatch contract works.
</purpose>

## Overview

GSD workflows expose extension points called "hook points" where capabilities can inject behavior.
Hooks are resolved via the capability registry and dispatched by the loop host. All hooks follow
a common dispatch contract defined in `loop-hook-dispatch.md`.

**Key locations:**
- Capability registry: `~/.claude/gsd-core/bin/lib/capability-registry.cjs`
- Dispatch contract: `~/.claude/gsd-core/references/loop-hook-dispatch.md`
- Loop resolver: `~/.claude/gsd-core/bin/lib/loop-resolver.cjs`

## Hook Points

GSD defines 12 hook points across the lifecycle:

| Point | Workflow | Timing |
|-------|-----------|--------|
| `discuss:pre` | `/gsd-discuss-phase` | Before phase discussion |
| `discuss:post` | `/gsd-discuss-phase` | After phase discussion |
| `plan:pre` | `/gsd-plan-phase` | Before planning |
| `plan:post` | `/gsd-plan-phase` | After planning |
| `execute:pre` | `/gsd-execute-phase` | Before execution |
| `execute:wave:pre` | `/gsd-execute-phase` | Before each wave |
| `execute:wave:post` | `/gsd-execute-phase` | After each wave |
| `execute:post` | `/gsd-execute-phase` | After execution |
| `verify:pre` | `/gsd-validate-phase` | Before verification |
| `verify:post` | `/gsd-validate-phase` | After verification |
| `ship:pre` | `/gsd-ship` | Before PR creation |
| `ship:post` | `/gsd-ship` | After PR creation |

**Note:** `/gsd-pr-branch` has **no hook points** — it's a pure git operation that filters
transient `.planning/` commits without dispatching capability hooks.

## Hook Dispatch Contract

All hooks share a common envelope shape:

```json
{
  "point": "ship:pre",
  "activeHooks": [
    { "kind": "gate", "check": { "predicate": {...} }, "blocking": true, "onError": "halt" },
    { "kind": "step", "ref": { "agent": "gsd-mempalace-curator" }, "onError": "skip" }
  ],
  "rendered": "..."
}
```

### Hook Kinds

| Kind | Purpose | Dispatch Method |
|------|---------|----------------|
| `contribution` | Inject fragment into a role's context | Embed `fragment.inline` verbatim |
| `step` | Dispatch a skill or agent | `Skill(skill="gsd-{ref.skill}")` or `Agent(subagent_type=ref.agent)` |
| `gate` | Evaluate a blocking check | Run `check.query` / `check.predicate` / `check.agentVerdict` |

### Blocking and Error Handling

- `blocking: true` → if check returns `block: true`, surface message and stop
- `blocking: false` → advisory only; surface message but continue
- `onError: halt` → on check error, surface error and stop
- `onError: skip` → on error, log warning and continue

### Resolving Hooks

Hooks are resolved via the capability registry:

```bash
gsd_run loop render-hooks ship:pre --raw
```

Output is JSON with `activeHooks` array containing only hooks whose `when` condition evaluates true.

## `/gsd-ship` Lifecycle Events

The ship workflow has two hook points with distinct semantics:

### `ship:pre` — Gates Executed Before PR Creation

**Resolution:**

```bash
SHIP_PRE_HOOKS_JSON=$(gsd_run loop render-hooks ship:pre --raw)
```

Read `activeHooks` array from the JSON response.

#### Security Enforcement Gate

**Capability:** `security`

**When active:** `workflow.security_enforcement = true` (default: `true`)

**Hook definition:**

```json
{
  "point": "ship:pre",
  "kind": "gate",
  "check": {
    "predicate": {
      "kind": "artifact-frontmatter-equals",
      "artifact": "SECURITY.md",
      "field": "threats_open",
      "equals": 0
    }
  },
  "blocking": true,
  "onError": "halt"
}
```

**Behavior:**

1. Check if `SECURITY.md` exists in phase directory
2. If missing → block with `SECURITY_SHIP_GATE_NO_REVIEW`:
   ```
   ⚠ Security enforcement is enabled but no SECURITY.md exists for this phase.
   Run /gsd-secure-phase {phase} and resolve findings before shipping.
   ```
3. If exists → read frontmatter `threats_open`
4. If `threats_open == 0` → gate passes; continue
5. If `threats_open > 0` or missing/unparseable → **fail closed** with `SECURITY_SHIP_GATE_OPEN_THREATS`:
   ```
   ⚠ Security ship gate: SECURITY.md does not assert threats_open == 0 (found: {threats_open|unset}).
   Resolve open threats (or re-run /gsd-secure-phase {phase}) before shipping.
   ```

**Config controls:**

| Config key | Type | Default | Description |
|------------|------|---------|-------------|
| `workflow.security_enforcement` | boolean | `true` | Enable security threat-mitigation verification |
| `workflow.security_asvs_level` | number | `1` | OWASP ASVS level for security review |
| `workflow.security_block_on` | enum | `"high"` | Minimum threat severity that blocks |

#### Broken-Windows Ledger Gate

**Capability:** `broken-windows`

**When active:** `workflow.windows_enforce = true` (default: `false` — opt-in)

**Hook definition:**

```json
{
  "point": "ship:pre",
  "kind": "gate",
  "check": {
    "predicate": {
      "kind": "artifact-frontmatter-equals",
      "artifact": "WINDOWS.md",
      "field": "open_count",
      "equals": 0
    }
  },
  "blocking": true,
  "onError": "halt"
}
```

**Behavior:**

1. Read ledger status: `gsd_run windows status --raw`
2. Extract `ledger.open_count`
3. If `open_count == 0` → gate passes; continue
4. If `open_count > 0` → block with `WINDOWS_SHIP_GATE_OPEN`:
   ```
   ⚠ Broken-windows ship gate: WINDOWS.md has {open_count} open window(s).
   Resolve each entry before shipping, or explicitly waive with a recorded reason:
     gsd_run windows fixed <id>      # defect resolved
     gsd_run windows waive <id> "<reason>"   # justified deferral (reason required)
   Then re-run /gsd-ship.
   ```
5. If `open_count` is `"?"`, empty, or non-numeric → **fail closed** with `WINDOWS_SHIP_GATE_READ_FAILED`:
   ```
   ⚠ Broken-windows ship gate: could not read open_count from .planning/WINDOWS.md.
   Inspect the file or run `gsd_run windows status --raw` to diagnose. The ledger
   may be malformed; fix it before shipping (an unparseable ledger is a broken window).
   ```

**Ledger is optional and backward-compatible:** If `WINDOWS.md` doesn't exist or is empty,
the gate passes silently. The gate only blocks when at least one entry is `open`.

**Config control:**

| Config key | Type | Default | Description |
|------------|------|---------|-------------|
| `workflow.windows_enforce` | boolean | `false` | Enable blocking ship:pre gate for broken-windows |

**Manual commands:**

```bash
# Mark a window as resolved
gsd-tools windows fixed <id>

# Waive with recorded reason (deferral)
gsd-tools windows waive <id> "Not blocking current milestone; tracked for follow-up"

# Check ledger status
gsd-tools windows status --raw
```

#### TDD Audit Trail Reconstruction

**Not a capability hook** — this is inline behavior in the ship workflow.

**Behavior:**

1. Walk PR branch commits (merges excluded) via:
   ```bash
   RANGE_BASE=$(git merge-base "${BASE_BRANCH}" HEAD)
   git log "${RANGE_BASE}..HEAD" --no-merges --reverse \
     --format='%H%x1f%s%x1f%(trailers:key=gate_status,valueonly,separator=%x2c)%x1e'
   ```

2. Pair commits by conventional-commit type:
   - `test:` commit → RED row, paired with next `feat:` or `fix:` as Impl commit
   - `refactor:`, `docs:`, `chore:` → standalone rows with Impl commit `—`
   - `feat:`/`fix:` without preceding `test:` → standalone rows

3. Normalize `gate_status:` values to: `skill`, `fallback`, `exempt`, `missing`

4. **Self-suppress when 100% missing:** If every commit normalizes to `missing`, skip the entire section — TDD mode was off, so the table would be pure noise.

5. Emit `## TDD Audit` section in PR body with table and aggregate trailer on final line:
   ```
   gate_status: skill=2, fallback=1, exempt=1, missing=0
   ```

**This section is informational only** — it never blocks the ship.

### `ship:post` — Steps Executed After PR Creation

**Resolution:**

```bash
SHIP_POST_HOOKS_JSON=$(gsd_run loop render-hooks ship:post --raw)
```

Read `activeHooks` array from the JSON response.

#### MemPalace Curation

**Capability:** `mempalace`

**When active:** `mempalace.enabled = true` (default: `false`)

**Hook definition:**

```json
{
  "point": "ship:post",
  "kind": "step",
  "ref": {
    "agent": "gsd-mempalace-curator"
  },
  "consumes": ["UAT.md"],
  "onError": "skip"
}
```

**Agent:** `gsd-mempalace-curator`

**Consumes:** `UAT.md`

**Behavior:**

The agent executes four independent tasks, each best-effort:

1. **Diary entry** (when `mempalace.diary_journal = true`)
   - Write one concise per-phase diary entry
   - Tool: `mempalace_diary_write(agent_name=<project>/<role>, entry=<summary>, topic="phase-ship", wing=<wing>)`
   - **Idempotency:** Check for existing entry keyed by `(wing, agent_name, topic, phase-id)` and update in place

2. **extract-learnings → KG mirror** (when `mempalace.mirror_kg = true`)
   - For each decision/lesson/pattern/surprise from phase learnings, add typed KG triple
   - Include provenance (`source_file`, `source_drawer_id`) and `valid_from` = phase date
   - **Idempotency:** Query for existing triple `(subject, predicate, object)` first; skip if exists with same `valid_from`
   - Superseded decisions: call `mempalace_kg_invalidate` to set `valid_to` rather than delete

3. **Cross-project tunnels** (when `mempalace.cross_project_tunnels = true`)
   - Use `mempalace_find_tunnels` to surface related wings
   - Create tunnel only for connections with justification
   - **Idempotency:** Check `find_tunnels` result and skip if tunnel already exists

4. **Wing-scoped prune** (optional)
   - Run `mempalace sync --wing <wing> --apply` to prune drawers whose source artifacts were archived/deleted
   - **NEVER** run global sync/prune — always pass `--wing`

**Error handling:** `onError: skip` — any failure logs a warning but never fails the ship step.

**Hard rules enforced by agent:**

- Best-effort only — never propagate an error that would fail `ship:post`
- Wing-scoped only — never read, write, or prune outside this project's wing
- Verbatim preservation — invalidate superseded facts (set `valid_to`); do not destroy history
- Idempotent — re-running a shipped phase must not duplicate entries, facts, or tunnels

**Report:** Emit short summary: "diary (yes/no), KG facts mirrored (count), tunnels proposed/created (count), drawers pruned (count)" or "MemPalace unavailable — curation skipped"

**Config controls:**

| Config key | Type | Default | Description |
|------------|------|---------|-------------|
| `mempalace.enabled` | boolean | `false` | Master toggle for MemPalace capability |
| `mempalace.memory_mode` | enum | `"augment"` | How palace relates to native memory (`augment` / `kg_backend` / `replace`) |
| `mempalace.wing` | string | `""` | Palace wing name (empty derives from `project_code` or dir) |
| `mempalace.diary_journal` | boolean | `true` | Write per-agent diary entry at `ship:post` |
| `mempalace.mirror_kg` | boolean | `true` | Mirror decisions/learnings into temporal KG |
| `mempalace.cross_project_tunnels` | boolean | `false` | Propose/create cross-wing tunnels at `ship:post` |

### Runtime-Aware Dispatch

Before dispatching the agent, resolve its dispatch type for the current runtime:

```bash
DISPATCH_TYPE=$(gsd_run query resolve-dispatch-type --requested gsd-mempalace-curator --raw)
```

On Claude/OpenCode/named-dispatch runtimes, returns `"gsd-mempalace-curator"`.
On kimi-code (built-ins-only runtime), maps to `"coder"` / `"explore"` / `"plan"` by role-suffix.

**Model resolution:**

```bash
HOOK_AGENT_MODEL=$(gsd_run query resolve-model "gsd-mempalace-curator" --raw 2>/dev/null || true)
```

Omit `model=` parameter entirely when resolved model is `inherit` or empty (prevents 404 on non-Claude runtimes).

## `/gsd-pr-branch` Lifecycle Events

**No hook points registered.**

The `/gsd-pr-branch` workflow is a pure git operation that creates a clean branch for PR review
without dispatching capability hooks.

### Workflow Behavior

1. **Detect state:** Parse arguments for target branch, detect commits ahead
2. **Handle sub-repos:** If `planning.sub_repos` configured, process dirty repos:
   - Stage explicit changed files (never `git add -A`)
   - Create branch with repo slug: `{branch}-{repo-safe}-pr`
   - Commit, push with `--set-upstream`
   - Open companion PR via `gh pr create`
3. **Analyze commits:** Classify as:
   - **Code commits** (touch non-`.planning/` files) → INCLUDE
   - **Structural planning commits** (touch only STATE.md/ROADMAP.md/etc.) → INCLUDE
   - **Transient planning commits** (touch only phases/quick/research/etc.) → EXCLUDE
4. **Create PR branch:** Cherry-pick included commits with path filtering:
   ```bash
   for dir in phases quick research threads todos debug seeds codebase ui-reviews; do
     git rm -r --cached ".planning/$dir/" 2>/dev/null || true
   done
   ```
5. **Verify:** Confirm no transient `.planning/` files in PR branch

### Sub-Repo Handling

When `planning.sub_repos` is configured and dirty repos are detected:

```
Sub-repos with uncommitted changes:
  backend
  frontend

How should sub-repo changes be handled?
  1. all    — branch, commit (explicit files only), push -u, open companion PR per repo
  2. select — choose which sub-repos to process
  3. skip   — ignore sub-repos, continue with root repo only
```

All sub-repo git work happens via the `pr-subrepo` query seam — it validates paths through
symlinks, stages explicit files only, and runs git in a containment-checked directory.

## Hook Point Summary

| Workflow | Hook Points | Active Hooks |
|----------|-------------|--------------|
| `/gsd-ship` | `ship:pre`, `ship:post` | Security gate, broken-windows gate (opt-in), MemPalace curation (opt-in) |
| `/gsd-pr-branch` | None | — |
| `/gsd-discuss-phase` | `discuss:pre`, `discuss:post` | MemPalace recall/capture (opt-in) |
| `/gsd-plan-phase` | `plan:pre`, `plan:post` | AI integration, API coverage, MemPalace recall/capture (opt-in) |
| `/gsd-execute-phase` | `execute:pre`, `execute:wave:pre`, `execute:wave:post`, `execute:post` | MemPalace capture (opt-in) |
| `/gsd-validate-phase` | `verify:pre`, `verify:post` | API coverage gate, security audit (opt-in), MemPalace capture (opt-in) |

## CLI Commands for Hook Inspection

```bash
# Resolve active hooks at a point
gsd-tools loop render-hooks ship:pre --raw
gsd-tools loop render-hooks ship:post --raw

# Check broken-windows ledger status
gsd-tools windows status --raw

# Mark window as resolved
gsd-tools windows fixed <id>

# Waive window with reason
gsd-tools windows waive <id> "Tracked for follow-up"

# Resolve dispatch type for runtime
gsd-tools query resolve-dispatch-type --requested gsd-mempalace-curator --raw

# Resolve model for agent
gsd-tools query resolve-model gsd-mempalace-curator --raw
```

## References

- Capability registry: `~/.claude/gsd-core/bin/lib/capability-registry.cjs`
- Loop hook dispatch: `~/.claude/gsd-core/references/loop-hook-dispatch.md`
- Ship workflow: `~/.claude/gsd-core/workflows/ship.md`
- PR-branch workflow: `~/.claude/gsd-core/workflows/pr-branch.md`
- MemPalace curator agent: `~/.claude/agents/gsd-mempalace-curator.md`
- Loop host contract: `~/.claude/gsd-core/bin/lib/loop-host-contract.cjs`
- Loop resolver: `~/.claude/gsd-core/bin/lib/loop-resolver.cjs`
