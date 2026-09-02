# GSD Lifecycle Events

> **Generated:** 2026-08-21T23:15:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** gsd-core/bin/lib/capability-registry.cjs

<purpose>
Reference documentation for GSD's hook-based lifecycle events — which points fire on which
workflows, what capabilities register hooks at each point, and how the dispatch contract works.
</purpose>

## Overview

GSD workflows expose extension points called "hook points" where capabilities can inject behavior.
Hooks are resolved via the capability registry and dispatched by the loop host. All hooks follow
a common dispatch contract.

**Key locations:**
- Capability registry: `gsd-core/bin/lib/capability-registry.cjs`
- Loop resolver: `gsd-core/bin/lib/loop-resolver.cjs`

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
    { "kind": "gate", "check": { "predicate": {...} }, "blocking": true, "onError": "halt" }
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
gsd-tools loop render-hooks ship:pre --raw
```

Output is JSON with `activeHooks` array containing only hooks whose `when` condition evaluates true.

## `/gsd-discuss-phase` Lifecycle Events

No hooks registered at either `disc:pre` or `discuss:post` in this version.

## `/gsd-plan-phase` Lifecycle Events

### `plan:pre` — Steps Executed Before Planning

**Resolution:**

```bash
PLAN_PRE_HOOKS_JSON=$(gsd-tools loop render-hooks plan:pre --raw)
```

Read `activeHooks` array from the JSON response.

#### AI Integration Phase Step

**Capability:** `ai-integration`

**When active:** `workflow.ai_integration_phase = true`

**Hook definition:**

```json
{
  "kind": "step",
  "ref": { "skill": "ai-integration-phase" },
  "when": "workflow.ai_integration_phase",
  "produces": ["AI-SPEC.md"],
  "consumes": ["CONTEXT.md"],
  "onError": "skip"
}
```

**Behavior:** Dispatches `ai-integration-phase` skill to produce AI-SPEC.md.

#### Pattern Mapper Step

**Capability:** `pattern-mapper`

**When active:** `workflow.pattern_mapper = true`

**Hook definition:**

```json
{
  "kind": "step",
  "ref": { "agent": "gsd-pattern-mapper" },
  "when": "workflow.pattern_mapper",
  "onError": "skip"
}
```

**Behavior:** Dispatches `gsd-pattern-mapper` agent.

#### Research Step

**Capability:** `research`

**When active:** `workflow.research = true`

**Hook definition:**

```json
{
  "kind": "step",
  "ref": { "agent": "gsd-phase-researcher" },
  "when": "workflow.research",
  "produces": ["RESEARCH.md"],
  "consumes": ["CONTEXT.md"],
  "onError": "skip"
}
```

**Behavior:** Dispatches `gsd-phase-researcher` agent to produce RESEARCH.md.

#### UI Phase Step

**Capability:** `ui`

**When active:** `workflow.ui_phase = true`

**Hook definition:**

```json
{
  "kind": "step",
  "ref": { "skill": "ui-phase" },
  "when": "workflow.ui_phase",
  "produces": ["UI-SPEC.md"],
  "consumes": ["CONTEXT.md"],
  "onError": "skip"
}
```

**Behavior:** Dispatches `ui-phase` skill to produce UI-SPEC.md.

### `plan:post` — Gate Executed After Planning

**Resolution:**

```bash
PLAN_POST_HOOKS_JSON=$(gsd-tools loop render-hooks plan:post --raw)
```

#### Gap Analysis Gate

**Capability:** `gap-analysis`

**When active:** `workflow.post_planning_gaps = true`

**Hook definition:**

```json
{
  "kind": "gate",
  "when": "workflow.post_planning_gaps",
  "check": { "query": "gap-analysis.plan-post" },
  "blocking": false,
  "onError": "skip"
}
```

**Behavior:** Non-blocking gate that checks for planning gaps. Surfaces warning but never blocks.

## `/gsd-execute-phase` Lifecycle Events

### `execute:pre` — No Hooks Registered

### `execute:wave:pre` — No Hooks Registered

### `execute:wave:post` — Gates Executed After Each Wave

**Resolution:**

```bash
WAVE_POST_HOOKS_JSON=$(gsd-tools loop render-hooks execute:wave:post --raw)
```

#### Schema Drift Gate (Blocking)

**Capability:** `drift`

**When active:** `workflow.schema_drift_gate = true`

**Hook definition:**

```json
{
  "kind": "gate",
  "when": "workflow.schema_drift_gate",
  "check": { "query": "verify.schema-drift" },
  "blocking": true,
  "onError": "skip"
}
```

**Behavior:** Blocking gate that halts execution if schema drift is detected.

#### Codebase Drift Gate (Non-blocking)

**Capability:** `drift`

**When active:** `workflow.schema_drift_gate = true`

**Hook definition:**

```json
{
  "kind": "gate",
  "when": "workflow.schema_drift_gate",
  "check": { "query": "verify.codebase-drift" },
  "blocking": false,
  "onError": "skip"
}
```

**Behavior:** Non-blocking gate that warns about codebase drift but continues.

#### UI Safety Gate (Blocking)

**Capability:** `ui`

**When active:** `workflow.ui_safety_gate = true`

**Hook definition:**

```json
{
  "kind": "gate",
  "when": "workflow.ui_safety_gate",
  "check": { "query": "ui.safety-gate" },
  "blocking": true,
  "onError": "halt"
}
```

**Behavior:** Blocking gate that halts execution on UI safety violations.

### `execute:post` — Steps and Gates After Execution

**Resolution:**

```bash
EXECUTE_POST_HOOKS_JSON=$(gsd-tools loop render-hooks execute:post --raw)
```

#### Code Review Step

**Capability:** `code-review`

**When active:** `workflow.code_review = true`

**Hook definition:**

```json
{
  "kind": "step",
  "ref": { "skill": "code-review" },
  "when": "workflow.code_review",
  "produces": ["REVIEW.md"],
  "consumes": ["SUMMARY.md"],
  "onError": "skip"
}
```

**Behavior:** Dispatches `code-review` skill to produce REVIEW.md.

#### TDD Review Checkpoint Gate

**Capability:** `tdd`

**When active:** `workflow.tdd_mode = true`

**Hook definition:**

```json
{
  "kind": "gate",
  "when": "workflow.tdd_mode",
  "check": { "query": "tdd.review-checkpoint" },
  "blocking": false,
  "onError": "skip"
}
```

**Behavior:** Non-blocking gate that validates TDD mode checkpoint.

## `/gsd-validate-phase` Lifecycle Events

### `verify:pre` — Gate Executed Before Verification

**Resolution:**

```bash
VERIFY_PRE_HOOKS_JSON=$(gsd-tools loop render-hooks verify:pre --raw)
```

#### API Coverage Gate (Blocking)

**Capability:** `ai-integration`

**When active:** `workflow.api_coverage_gate = true`

**Hook definition:**

```json
{
  "kind": "gate",
  "when": "workflow.api_coverage_gate",
  "check": { "query": "api-coverage.verify-pre" },
  "blocking": true,
  "onError": "halt"
}
```

**Behavior:** Blocking gate that requires COVERAGE.md for API-integrating phases.

### `verify:post` — Steps Executed After Verification

**Resolution:**

```bash
VERIFY_POST_HOOKS_JSON=$(gsd-tools loop render-hooks verify:post --raw)
```

#### Nyquist Validation Step

**Capability:** `nyquist`

**When active:** `workflow.nyquist_validation = true`

**Hook definition:**

```json
{
  "kind": "step",
  "ref": { "skill": "validate-phase" },
  "when": "workflow.nyquist_validation",
  "produces": ["VALIDATION.md"],
  "consumes": ["SUMMARY.md"],
  "onError": "halt"
}
```

**Behavior:** Dispatches `validate-phase` skill to produce VALIDATION.md.

#### Security Phase Step

**Capability:** `security`

**When active:** `workflow.security_enforcement = true`

**Hook definition:**

```json
{
  "kind": "step",
  "ref": { "skill": "secure-phase" },
  "when": "workflow.security_enforcement",
  "produces": ["SECURITY.md"],
  "consumes": ["SUMMARY.md"],
  "onError": "halt"
}
```

**Behavior:** Dispatches `secure-phase` skill to produce SECURITY.md.

#### UI Review Step

**Capability:** `ui`

**When active:** `workflow.ui_review = true`

**Hook definition:**

```json
{
  "kind": "step",
  "ref": { "skill": "ui-review" },
  "when": "workflow.ui_review",
  "produces": ["UI-REVIEW.md"],
  "consumes": ["UI-SPEC.md"],
  "onError": "skip"
}
```

**Behavior:** Dispatches `ui-review` skill to produce UI-REVIEW.md.

## `/gsd-ship` Lifecycle Events

### `ship:pre` — Gate Executed Before PR Creation

**Resolution:**

```bash
SHIP_PRE_HOOKS_JSON=$(gsd-tools loop render-hooks ship:pre --raw)
```

#### Security Enforcement Gate

**Capability:** `security`

**When active:** `workflow.security_enforcement = true` (default: `true`)

**Hook definition:**

```json
{
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

### `ship:post` — No Hooks Registered

No hooks registered at `ship:post` in this version.

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

## Hook Point Summary

| Workflow | Hook Points | Active Hooks |
|----------|-------------|--------------|
| `/gsd-discuss-phase` | `discuss:pre`, `discuss:post` | None |
| `/gsd-plan-phase` | `plan:pre`, `plan:post` | AI integration, pattern mapper, research, UI, gap analysis |
| `/gsd-execute-phase` | `execute:pre`, `execute:wave:pre`, `execute:wave:post`, `execute:post` | Drift gates, UI safety gate, code review, TDD checkpoint |
| `/gsd-validate-phase` | `verify:pre`, `verify:post` | API coverage gate, Nyquist, security, UI review |
| `/gsd-ship` | `ship:pre`, `ship:post` | Security gate |
| `/gsd-pr-branch` | None | — |

## CLI Commands for Hook Inspection

```bash
# Resolve active hooks at a point
gsd-tools loop render-hooks plan:pre --raw
gsd-tools loop render-hooks execute:wave:post --raw
gsd-tools loop render-hooks ship:pre --raw

# Resolve dispatch type for runtime
gsd-tools query resolve-dispatch-type --requested gsd-mempalace-curator --raw

# Resolve model for agent
gsd-tools query resolve-model gsd-mempalace-curator --raw
```

## References

- Capability registry: `gsd-core/bin/lib/capability-registry.cjs`
- Loop resolver: `gsd-core/bin/lib/loop-resolver.cjs`
