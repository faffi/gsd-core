# GSD Lifecycle Visual Reference

> **Generated:** 2026-08-21T23:15:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** gsd-core/bin/lib/capability-registry.cjs

<purpose>
Visual diagram of the GSD lifecycle showing all workflows, hook points, and
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
                    │ (no hooks registered)               │ (no hooks registered)
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
                    │ ○ ai-integration (step)            │ ○ gap-analysis (gate, non-blocking)
                    │   when: workflow.ai_integration_phase│   when: workflow.post_planning_gaps
                    │                                     │
                    │ ○ pattern-mapper (step)            │
                    │   when: workflow.pattern_mapper     │
                    │                                     │
                    │ ○ research (step)                  │
                    │   when: workflow.research           │
                    │                                     │
                    │ ○ ui (step)                        │
                    │   when: workflow.ui_phase           │
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
                    │ (no hooks registered)               │ ○ drift (gate, blocking)
                    │                                     │   when: workflow.schema_drift_gate
                    │                                     │
                    │                                     │ ○ drift (gate, non-blocking)
                    │                                     │   when: workflow.schema_drift_gate
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
                    │ ○ ai-integration (gate, blocking)  │ ○ nyquist (step)
                    │   when: workflow.api_coverage_gate  │   when: workflow.nyquist_validation
                    │                                     │
                    │                                     │ ○ security (step)
                    │                                     │   when: workflow.security_enforcement
                    │                                     │
                    │                                     │ ○ ui (step)
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
                    │ ○ security (gate, blocking)        │ (no hooks registered)
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
| `discuss:pre` | — | — | — |
| `discuss:post` | — | — | — |

### `/gsd-plan-phase`

| Point | Kind | Capability | When Condition | Blocking |
|-------|------|------------|----------------|----------|
| `plan:pre` | step | ai-integration | `workflow.ai_integration_phase` | — |
| `plan:pre` | step | pattern-mapper | `workflow.pattern_mapper` | — |
| `plan:pre` | step | research | `workflow.research` | — |
| `plan:pre` | step | ui | `workflow.ui_phase` | — |
| `plan:post` | gate | gap-analysis | `workflow.post_planning_gaps` | false |

### `/gsd-execute-phase`

| Point | Kind | Capability | When Condition | Blocking |
|-------|------|------------|----------------|----------|
| `execute:pre` | — | — | — | — |
| `execute:wave:pre` | — | — | — | — |
| `execute:wave:post` | gate | drift | `workflow.schema_drift_gate` | **true** |
| `execute:wave:post` | gate | drift | `workflow.schema_drift_gate` | false |
| `execute:wave:post` | gate | ui | `workflow.ui_safety_gate` | **true** |
| `execute:post` | step | code-review | `workflow.code_review` | — |
| `execute:post` | gate | tdd | `workflow.tdd_mode` | false |

### `/gsd-validate-phase`

| Point | Kind | Capability | When Condition | Blocking |
|-------|------|------------|----------------|----------|
| `verify:pre` | gate | ai-integration | `workflow.api_coverage_gate` | **true** |
| `verify:post` | step | nyquist | `workflow.nyquist_validation` | — |
| `verify:post` | step | security | `workflow.security_enforcement` | — |
| `verify:post` | step | ui | `workflow.ui_review` | — |

### `/gsd-ship`

| Point | Kind | Capability | When Condition | Blocking |
|-------|------|------------|----------------|----------|
| `ship:pre` | gate | security | `workflow.security_enforcement` | **true** |
| `ship:post` | — | — | — | — |

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

### ai-integration (2 hooks)

- `plan:pre` step: `ai-integration-phase` skill (AI-SPEC design contract)
- `verify:pre` gate: **blocking** — requires COVERAGE.md for API-integrating phases

### code-review (1 hook)

- `execute:post` step: `code-review` skill post-execution

### drift (2 hooks)

- `execute:wave:post` gate: **blocking** schema drift detection
- `execute:wave:post` gate: non-blocking schema drift warning

### gap-analysis (1 hook)

- `plan:post` gate: non-blocking post-planning gap detection

### nyquist (1 hook)

- `verify:post` step: `validate-phase` skill (Nyquist validation architecture)

### pattern-mapper (1 hook)

- `plan:pre` step: `gsd-pattern-mapper` agent

### research (1 hook)

- `plan:pre` step: `gsd-phase-researcher` agent

### security (2 hooks)

- `verify:post` step: `secure-phase` skill (produces SECURITY.md)
- `ship:pre` gate: **blocking** — requires `SECURITY.md` frontmatter `threats_open == 0`

### tdd (1 hook)

- `execute:post` gate: non-blocking TDD mode validation

### ui (3 hooks)

- `plan:pre` step: `ui-phase` skill (produces UI-SPEC.md)
- `execute:wave:post` gate: **blocking** — UI safety gate during execution
- `verify:post` step: `ui-review` skill (visual quality audit)

## Blocking Gates Summary

These gates can halt workflow progression:

| Point | Capability | Default | Condition |
|-------|------------|---------|-----------|
| `execute:wave:post` | drift | `workflow.schema_drift_gate` | Schema drift detected |
| `execute:wave:post` | ui | `workflow.ui_safety_gate` | UI safety violation |
| `verify:pre` | ai-integration | `workflow.api_coverage_gate` | Missing COVERAGE.md for API phase |
| `ship:pre` | security | `workflow.security_enforcement` (true) | `SECURITY.md threats_open != 0` |

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

- Capability registry: `gsd-core/bin/lib/capability-registry.cjs`
- Loop resolver: `gsd-core/bin/lib/loop-resolver.cjs`
