# GSD Lifecycle Visual Reference

<purpose>
Visual diagram of the complete GSD lifecycle showing all workflows, hook points, and
capability hooks. Generated from the capability registry.
</purpose>

## Full Lifecycle Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    GSD LIFECYCLE                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

                              ┌──────────────────┐
                              │  /gsd-discuss    │
                              │    -phase        │
                              └────────┬─────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
                    ▼                                     ▼
        ┌───────────────────────┐             ┌───────────────────────┐
        │    discuss:pre        │             │    discuss:post       │
        └───────────┬───────────┘             └───────────┬───────────┘
                    │                                     │
                    │ ○ mempalace (contribution)         │ ○ mempalace (step: capture)
                    │   when: mempalace.enabled           │   when: mempalace.enabled
                    │                                     │
                    └──────────────────┬──────────────────┘
                                       │
                                       ▼
                              ┌──────────────────┐
                              │  /gsd-plan-phase │
                              └────────┬─────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
                    ▼                                     ▼
        ┌───────────────────────┐             ┌───────────────────────┐
        │     plan:pre          │             │     plan:post         │
        └───────────┬───────────┘             └───────────┬───────────┘
                    │                                     │
                    │ ○ ai-integration (step)            │ ○ mempalace (step: capture)
                    │   when: workflow.ai_integration_phase│   when: mempalace.enabled
                    │                                     │
                    │ ○ ai-integration (contribution)    │ ○ claude-orchestration (contribution)
                    │   when: workflow.api_coverage_gate  │   when: claude_orchestration.enabled
                    │                                     │
                    │ ○ assumption-delta (contribution)  │ ○ external-job (contribution)
                    │   when: workflow.assumption_delta   │   when: external_job.enabled
                    │                                     │
                    │ ○ drift (gate, non-blocking)       │ ○ gap-analysis (gate, non-blocking)
                    │   when: workflow.plan_drift_precheck│   when: workflow.post_planning_gaps
                    │                                     │
                    │ ○ intel (step: api-surface)        │
                    │   when: intel.enabled               │
                    │                                     │
                    │ ○ mempalace (step: recall)         │
                    │   when: mempalace.enabled           │
                    │                                     │
                    │ ○ pattern-mapper (step)            │
                    │   when: workflow.pattern_mapper     │
                    │                                     │
                    │ ○ research (step: researcher)      │
                    │   when: workflow.research           │
                    │                                     │
                    │ ○ schema-gate (contribution)       │
                    │   when: workflow.schema_push_detection
                    │                                     │
                    │ ○ security (contribution)          │
                    │   when: workflow.security_enforcement
                    │                                     │
                    │ ○ tdd (contribution)               │
                    │   when: workflow.tdd_mode           │
                    │                                     │
                    │ ○ ui (step: ui-phase)              │
                    │   when: workflow.ui_phase           │
                    │                                     │
                    │ ○ ui (gate, blocking)              │
                    │   when: workflow.ui_safety_gate     │
                    │                                     │
                    └──────────────────┬──────────────────┘
                                       │
                                       ▼
                              ┌──────────────────┐
                              │ /gsd-execute     │
                              │    -phase        │
                              └────────┬─────────┘
                                       │
                                       │  execute:pre
                                       │  (no hooks registered)
                                       │
                                       ▼
                              ┌──────────────────┐
                              │  Execute Loop    │
                              │  (per wave)      │
                              └────────┬─────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
                    ▼                                     ▼
        ┌───────────────────────┐             ┌───────────────────────┐
        │  execute:wave:pre     │             │  execute:wave:post    │
        └───────────┬───────────┘             └───────────┬───────────┘
                    │                                     │
                    │ ○ claude-orchestration (contrib)   │ ○ drift (gate, blocking)
                    │   when: claude_orchestration.enabled│   when: workflow.schema_drift_gate
                    │                                     │
                    │                                     │ ○ drift (gate, non-blocking)
                    │                                     │   when: workflow.schema_drift_gate
                    │                                     │
                    │                                     │ ○ external-job (contribution)
                    │                                     │   when: external_job.enabled
                    │                                     │
                    │                                     │ ○ mempalace (contribution)
                    │                                     │   when: mempalace.enabled
                    │                                     │
                    │                                     │ ○ ui (gate, blocking)
                    │                                     │   when: workflow.ui_safety_gate
                    │                                     │
                    └──────────────────┬──────────────────┘
                                       │
                                       │ (repeat per wave)
                                       │
                                       ▼
        ┌───────────────────────┐
        │    execute:post       │
        └───────────┬───────────┘
                    │
                    │ ○ code-review (step)
                    │   when: workflow.code_review
                    │
                    │ ○ tdd (gate, non-blocking)
                    │   when: workflow.tdd_mode
                    │
                    └──────────────────┬──────────────────┘
                                       │
                                       ▼
                              ┌──────────────────┐
                              │ /gsd-validate    │
                              │    -phase        │
                              └────────┬─────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
                    ▼                                     ▼
        ┌───────────────────────┐             ┌───────────────────────┐
        │     verify:pre        │             │     verify:post       │
        └───────────┬───────────┘             └───────────┬───────────┘
                    │                                     │
                    │ ○ ai-integration (gate, blocking)  │ ○ mempalace (step: capture)
                    │   when: workflow.api_coverage_gate  │   when: mempalace.enabled
                    │                                     │
                    │                                     │ ○ nyquist (step: validate)
                    │                                     │   when: workflow.nyquist_validation
                    │                                     │
                    │                                     │ ○ security (step: secure-phase)
                    │                                     │   when: workflow.security_enforcement
                    │                                     │
                    │                                     │ ○ ui (step: ui-review)
                    │                                     │   when: workflow.ui_review
                    │                                     │
                    └──────────────────┬──────────────────┘
                                       │
                                       ▼
                              ┌──────────────────┐
                              │   /gsd-ship      │
                              └────────┬─────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
                    ▼                                     ▼
        ┌───────────────────────┐             ┌───────────────────────┐
        │     ship:pre          │             │     ship:post         │
        └───────────┬───────────┘             └───────────┬───────────┘
                    │                                     │
                    │ ○ broken-windows (gate, blocking)  │ ○ mempalace (step: curator)
                    │   when: workflow.windows_enforce    │   when: mempalace.enabled
                    │   (opt-in, default: false)          │
                    │                                     │
                    │ ○ security (gate, blocking)        │
                    │   when: workflow.security_enforcement
                    │   (default: true)                   │
                    │                                     │
                    └──────────────────┬──────────────────┘
                                       │
                                       ▼
                              ┌──────────────────┐
                              │   PR Created     │
                              └──────────────────┘
```

## Hook Points by Workflow

### `/gsd-discuss-phase`

| Point | Kind | Capability | When Condition |
|-------|------|------------|----------------|
| `discuss:pre` | contribution | mempalace | `mempalace.enabled` |
| `discuss:post` | step | mempalace | `mempalace.enabled` |

### `/gsd-plan-phase`

| Point | Kind | Capability | When Condition | Blocking |
|-------|------|------------|----------------|----------|
| `plan:pre` | step | ai-integration | `workflow.ai_integration_phase` | — |
| `plan:pre` | contribution | ai-integration | `workflow.api_coverage_gate` | — |
| `plan:pre` | contribution | assumption-delta | `workflow.assumption_delta` | — |
| `plan:pre` | gate | drift | `workflow.plan_drift_precheck` | false |
| `plan:pre` | step | intel | `intel.enabled` | — |
| `plan:pre` | step | mempalace | `mempalace.enabled` | — |
| `plan:pre` | step | pattern-mapper | `workflow.pattern_mapper` | — |
| `plan:pre` | step | research | `workflow.research` | — |
| `plan:pre` | contribution | schema-gate | `workflow.schema_push_detection` | — |
| `plan:pre` | contribution | security | `workflow.security_enforcement` | — |
| `plan:pre` | contribution | tdd | `workflow.tdd_mode` | — |
| `plan:pre` | step | ui | `workflow.ui_phase` | — |
| `plan:pre` | gate | ui | `workflow.ui_safety_gate` | **true** |
| `plan:post` | step | mempalace | `mempalace.enabled` | — |
| `plan:post` | contribution | claude-orchestration | `claude_orchestration.enabled` | — |
| `plan:post` | contribution | external-job | `external_job.enabled` | — |
| `plan:post` | gate | gap-analysis | `workflow.post_planning_gaps` | false |

### `/gsd-execute-phase`

| Point | Kind | Capability | When Condition | Blocking |
|-------|------|------------|----------------|----------|
| `execute:pre` | — | — | — | — |
| `execute:wave:pre` | contribution | claude-orchestration | `claude_orchestration.enabled` | — |
| `execute:wave:post` | gate | drift | `workflow.schema_drift_gate` | **true** |
| `execute:wave:post` | gate | drift | `workflow.schema_drift_gate` | false |
| `execute:wave:post` | contribution | external-job | `external_job.enabled` | — |
| `execute:wave:post` | contribution | mempalace | `mempalace.enabled` | — |
| `execute:wave:post` | gate | ui | `workflow.ui_safety_gate` | **true** |
| `execute:post` | step | code-review | `workflow.code_review` | — |
| `execute:post` | gate | tdd | `workflow.tdd_mode` | false |

### `/gsd-validate-phase`

| Point | Kind | Capability | When Condition | Blocking |
|-------|------|------------|----------------|----------|
| `verify:pre` | gate | ai-integration | `workflow.api_coverage_gate` | **true** |
| `verify:post` | step | mempalace | `mempalace.enabled` | — |
| `verify:post` | step | nyquist | `workflow.nyquist_validation` | — |
| `verify:post` | step | security | `workflow.security_enforcement` | — |
| `verify:post` | step | ui | `workflow.ui_review` | — |

### `/gsd-ship`

| Point | Kind | Capability | When Condition | Blocking |
|-------|------|------------|----------------|----------|
| `ship:pre` | gate | broken-windows | `workflow.windows_enforce` | **true** |
| `ship:pre` | gate | security | `workflow.security_enforcement` | **true** |
| `ship:post` | step | mempalace | `mempalace.enabled` | — |

### `/gsd-pr-branch`

**No hook points registered** — pure git operation.

## Hook Kind Legend

| Kind | Symbol | Description |
|------|--------|-------------|
| step | ● | Dispatches a skill or agent |
| contribution | ○ | Injects fragment into a role's context |
| gate (blocking) | 🔴 | Must pass to continue |
| gate (non-blocking) | 🟡 | Advisory; continues regardless |

## Capability Hook Summary

### ai-integration (3 hooks)

- `plan:pre` step: `ai-integration-phase` skill (AI-SPEC design contract)
- `plan:pre` contribution: API coverage checkpoint instructions for planner
- `verify:pre` gate: **blocking** — requires COVERAGE.md for API-integrating phases

### assumption-delta (1 hook)

- `plan:pre` contribution: Assumption tracking instructions for planner

### broken-windows (1 hook)

- `ship:pre` gate: **blocking** — requires `WINDOWS.md` frontmatter `open_count == 0`

### claude-orchestration (2 hooks)

- `execute:wave:pre` contribution: Claude-specific orchestration hints for executor
- `plan:post` contribution: Claude-specific planning hints

### code-review (1 hook)

- `execute:post` step: `code-review` skill post-execution

### drift (3 hooks)

- `plan:pre` gate: non-blocking plan drift precheck
- `execute:wave:post` gate: **blocking** schema drift detection
- `execute:wave:post` gate: non-blocking schema drift warning

### external-job (2 hooks)

- `execute:wave:post` contribution: External job integration for executor
- `plan:post` contribution: External job integration for planner

### gap-analysis (1 hook)

- `plan:post` gate: non-blocking post-planning gap detection

### intel (1 hook)

- `plan:pre` step: `intel api-surface` command (updates API-SURFACE.md)

### mempalace (7 hooks)

- `discuss:pre` contribution: Memory recall instructions for orchestrator
- `discuss:post` step: `mempalace-capture` skill (captures CONTEXT.md)
- `plan:pre` step: `mempalace-recall` skill (produces MEMORY-RECALL.md)
- `plan:post` step: `mempalace-capture` skill (captures PLAN.md)
- `execute:wave:post` contribution: Problem→fix capture instructions for verifier
- `verify:post` step: `mempalace-capture` skill (captures SUMMARY.md)
- `ship:post` step: `gsd-mempalace-curator` agent (diary, KG mirror, tunnels, prune)

### nyquist (1 hook)

- `verify:post` step: `validate-phase` skill (Nyquist validation architecture)

### pattern-mapper (1 hook)

- `plan:pre` step: `gsd-pattern-mapper` agent

### research (1 hook)

- `plan:pre` step: `gsd-phase-researcher` agent

### schema-gate (1 hook)

- `plan:pre` contribution: Schema push detection instructions for planner

### security (3 hooks)

- `plan:pre` contribution: Threat model instructions for planner
- `verify:post` step: `secure-phase` skill (produces SECURITY.md)
- `ship:pre` gate: **blocking** — requires `SECURITY.md` frontmatter `threats_open == 0`

### tdd (2 hooks)

- `plan:pre` contribution: TDD cycle instructions for planner
- `execute:post` gate: non-blocking TDD mode validation

### ui (4 hooks)

- `plan:pre` step: `ui-phase` skill (produces UI-SPEC.md)
- `plan:pre` gate: **blocking** — requires UI-SPEC.md for frontend phases
- `execute:wave:post` gate: **blocking** — UI safety gate during execution
- `verify:post` step: `ui-review` skill (visual quality audit)

## Blocking Gates Summary

These gates can halt workflow progression:

| Point | Capability | Default | Condition |
|-------|------------|---------|-----------|
| `plan:pre` | ui | `workflow.ui_safety_gate` | Requires UI-SPEC.md for frontend phases |
| `execute:wave:post` | drift | `workflow.schema_drift_gate` | Schema drift detected |
| `execute:wave:post` | ui | `workflow.ui_safety_gate` | UI safety violation |
| `verify:pre` | ai-integration | `workflow.api_coverage_gate` | Missing COVERAGE.md for API phase |
| `ship:pre` | security | `workflow.security_enforcement` (true) | `SECURITY.md threats_open != 0` |
| `ship:pre` | broken-windows | `workflow.windows_enforce` (false) | `WINDOWS.md open_count != 0` |

## Hook Resolution Workflow

For each hook point, orchestrator:

1. **Resolve hooks:**
   ```bash
   gsd-tools loop render-hooks <point> --raw
   ```

2. **Read `activeHooks` array** — contains only hooks whose `when` condition is true

3. **Dispatch by kind:**
   - `contribution` → embed `fragment.inline` into role context
   - `step` → dispatch `ref.skill` via Skill tool or `ref.agent` via Agent tool
   - `gate` → evaluate `check.query` / `check.predicate` / `check.agentVerdict`

4. **Handle blocking:**
   - `blocking: true` + check fails → surface message and stop
   - `blocking: false` + check fails → surface message and continue

5. **Handle errors:**
   - `onError: halt` → surface error and stop
   - `onError: skip` → log warning and continue

## References

- Capability registry: `~/.claude/gsd-core/bin/lib/capability-registry.cjs`
- Loop hook dispatch: `~/.claude/gsd-core/references/loop-hook-dispatch.md`
- Hook resolution CLI: `gsd-tools loop render-hooks <point> --raw`
