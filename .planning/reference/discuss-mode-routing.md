# `workflow.discuss_mode` — Discuss-Phase Mode Routing

> **Generated:** 2026-08-30T00:00:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** `commands/gsd/discuss-phase.md`, `gsd-core/workflows/discuss-phase.md`, `gsd-core/workflows/discuss-phase-assumptions.md`, `gsd-core/workflows/list-phase-assumptions.md`, `agents/gsd-assumptions-analyzer.md`, `gsd-core/bin/shared/config-defaults.manifest.json`, `gsd-core/references/planning-config.md`

<purpose>
Reference documentation for the `workflow.discuss_mode` config gate — which of two structurally
different discuss-phase workflows runs, how routing is resolved, and how it differs from the
similarly-named `--assumptions` CLI flag (a separate, unrelated mechanism).
</purpose>

## Overview

`/gsd:discuss-phase` produces `CONTEXT.md` — the artifact `gsd-phase-researcher` and `gsd-planner`
read to know what's already decided. There are **two independent ways to get there**:

| Mode | Method | Interactions | Output |
|------|--------|---------------|--------|
| `discuss` (default) | Interview — Claude asks, user answers | ~15-20 questions | `CONTEXT.md` |
| `assumptions` | Codebase-first — Claude analyzes, user corrects | ~2-4 corrections | `CONTEXT.md` (identical format) |

Both produce the **same CONTEXT.md schema** — downstream agents cannot tell which mode produced
the file they're reading.

## Config Key

| Key | Type | Default | Allowed Values |
|-----|------|---------|-----------------|
| `workflow.discuss_mode` | string | `"discuss"` | `"discuss"`, `"assumptions"` |

**Source of default:** `gsd-core/bin/shared/config-defaults.manifest.json:42`

**Description** (`gsd-core/references/planning-config.md:271`):
> Default mode for discuss-phase: `"discuss"` runs interactive questioning; `"assumptions"`
> analyzes codebase and surfaces assumptions instead

### Setting It

```bash
gsd-tools config-set workflow.discuss_mode assumptions
```

Or via `/gsd-settings` (interactive), or directly in `.planning/config.json`:

```json
{
  "workflow": {
    "discuss_mode": "assumptions"
  }
}
```

## Where It's Read

`commands/gsd/discuss-phase.md:51` (and its skill twin, `skills/gsd-discuss-phase/SKILL.md:51`
— byte-identical body):

```bash
DISCUSS_MODE=$(gsd_run query config-get workflow.discuss_mode --raw 2>/dev/null || echo "discuss")
```

If the config-get call fails (e.g. no config exists yet), the shell fallback (`|| echo "discuss"`)
supplies the default — the JS-side default in `config-defaults.manifest.json` is a second layer of
the same fallback, not the only one.

## Routing Logic

`commands/gsd/discuss-phase.md:54-62`:

```
If --assumptions is in $ARGUMENTS:
  → list-phase-assumptions.md   (STOP — config is never consulted)

Otherwise, if DISCUSS_MODE == "assumptions":
  → discuss-phase-assumptions.md

Otherwise ("discuss" / unset / any other value):
  → discuss-phase.md
```

**Precedence:** the `--assumptions` CLI flag is checked *first* and short-circuits before
`DISCUSS_MODE` is even read. This means `--assumptions` always wins regardless of what
`workflow.discuss_mode` is configured to.

## The Naming Collision

The CLI flag `--assumptions` and the config value `"assumptions"` share a name but route to
**two unrelated workflow files** with different contracts. This is a source of confusion worth
tracking explicitly:

| | `--assumptions` flag | `discuss_mode: "assumptions"` |
|---|---|---|
| **Workflow file** | `list-phase-assumptions.md` | `discuss-phase-assumptions.md` |
| **Writes CONTEXT.md?** | **No** — purely conversational | **Yes** — identical schema to `discuss` mode |
| **Purpose** | Quick gut-check before running full discuss | Full replacement for the interview |
| **Invocation** | `/gsd:discuss-phase 3 --assumptions` | `/gsd:discuss-phase 3` (config-driven) |
| **Persists anything?** | No | Yes — `CONTEXT.md` + `DISCUSSION-LOG.md` |

## Mode 1 (default): `discuss` → `discuss-phase.md`

**Philosophy** (`discuss-phase.md:52-59`): *"User = founder/visionary. Claude = builder."*

The user knows: how they imagine it working, what it should look/feel like, essential vs.
nice-to-have, specific references. The user doesn't know (and shouldn't be asked): codebase
patterns, technical risks, implementation approach — those are research/planning's job.

**Process:**
1. Load prior context (PROJECT.md, REQUIREMENTS.md, STATE.md, prior CONTEXT.md files)
2. Scout codebase for reusable assets and patterns
3. Analyze phase — identify gray areas, skip anything already decided in prior phases
4. Present remaining gray areas — user selects which to discuss
5. Deep-dive each selected area via `AskUserQuestion` until satisfied
6. Write `CONTEXT.md`

**Byte budget:** the main file is capped at 32,000 bytes (#717); per-mode bodies (`--power`,
`--all`, `--auto`, `--chain`, `--text`, `--batch`, `--analyze`, advisor) are lazy-loaded overlays
under `gsd-core/workflows/discuss-phase/modes/` — only the file matching the active flag is read.

## Mode 2: `assumptions` → `discuss-phase-assumptions.md`

**Philosophy** (`discuss-phase-assumptions.md:24-35`): *"You are a thinking partner, not an
interviewer."* Read the codebase FIRST, form opinions SECOND, ask ONLY about what's genuinely
unclear.

**Process:**

1. **`initialize`** — parse phase arg, resolve `ANALYZER_MODEL` (honors `model_overrides` /
   `models.discuss` via the routed-model resolver, #2072)
2. **`check_existing`** — if CONTEXT.md already exists, offer update/view/skip
3. **`load_prior_context`** — read PROJECT.md, REQUIREMENTS.md, STATE.md, all prior
   `*-CONTEXT.md` files (decisions from phases < current are locked priors)
4. **`cross_reference_todos`** — fold matching pending todos into scope (`todo.match-phase`)
5. **`load_methodology`** — read `.planning/METHODOLOGY.md` if present; named lenses shape how
   assumptions are generated and flagged (optional artifact)
6. **`scout_codebase`** — lightweight scan: reuse `.planning/codebase/*.md` maps if present,
   else targeted grep on phase-goal keywords
7. **`deep_codebase_analysis`** — spawns `gsd-assumptions-analyzer` (see below) to do the actual
   file reading, keeping raw source out of the orchestrator's context window
8. **`external_research`** — skipped unless the analyzer flagged `needs_research[]`; spawns a
   `general-purpose` research agent (Context7 for library questions, WebSearch for ecosystem
   questions) only when gaps exist
9. **`present_assumptions`** — displays assumptions grouped by area with confidence badges;
   single `AskUserQuestion`: *"These all look right?"* → "Yes, proceed" or "Let me correct some"
10. **`correct_assumptions`** — multiSelect of wrong assumptions, one focused follow-up question
    per selected item (skipped if no corrections needed)
11. **`write_context`** — writes `CONTEXT.md` in the **same 6-section format** as `discuss` mode
    (`domain`, `decisions`, `canonical_refs`, `code_context`, `specifics`, `deferred`)
12. **`write_discussion_log`** — writes `DISCUSSION-LOG.md` tagged `Mode: assumptions`, an audit
    trail of what was assumed vs. corrected (explicitly *not* input to downstream agents)
13. **`git_commit`**, **`update_state`**, **`confirm_creation`**, **`auto_advance`**

### Calibration Tier

Before spawning the analyzer, the workflow resolves a calibration tier from
`USER-PROFILE.md`'s Vendor Choices/Philosophy rating (or a project-level
`config.json > preferences.vendor_philosophy` override, which takes priority):

| Vendor philosophy | Tier | Behavior |
|---|---|---|
| `conservative`, `thorough-evaluator` | `full_maturity` | 3-5 areas, 2-3 alternatives per Likely/Unclear item |
| `opinionated` | `minimal_decisive` | 2-3 areas, single decisive recommendation per item |
| anything else / no profile | `standard` | 3-4 areas, 2 alternatives per Likely/Unclear item |

This is the same axis documented in the user's developer-profile Vendor Choices directive: the
more decisive/opinionated the user's general stance, the fewer alternatives the analyzer surfaces
before recommending one.

### `gsd-assumptions-analyzer` Agent

**Definition:** `agents/gsd-assumptions-analyzer.md`
**Tools:** Read, Bash, Grep, Glob, Skill (read-only — cannot write files)
**Spawned by:** `discuss-phase-assumptions.md` step `deep_codebase_analysis`

**Input prompt includes:** phase goal, prior decisions summary, codebase scout hints,
calibration tier.

**Required output format** — a fixed contract the orchestrator parses:

```markdown
## Assumptions

### [Area Name]
- **Assumption:** [Decision statement]
  - **Why this way:** [Evidence — cite file paths]
  - **If wrong:** [Concrete consequence]
  - **Confidence:** Confident | Likely | Unclear

## Needs External Research
[Topics needing research beyond the codebase, or empty]
```

Confidence levels drive `--auto` behavior downstream: `Confident`/`Likely` proceed silently;
`Unclear` items get the recommended alternative auto-selected (with a log line) rather than
blocking on a question.

### Why This Mode Exists

Trades interview thoroughness for speed by leaning on codebase evidence instead of asking the
user to answer questions Claude could resolve by reading the code. Target: ~2-4 user
interactions instead of ~15-20.

## Mode 3 (flag, not config): `--assumptions` → `list-phase-assumptions.md`

Distinct mechanism — **not** gated by `workflow.discuss_mode`. Invoked explicitly:

```bash
/gsd:discuss-phase 3 --assumptions
```

**Key difference from both discuss_mode values** (`list-phase-assumptions.md:1-5`):
> This is ANALYSIS of what Claude thinks, not INTAKE of what user knows. No file output —
> purely conversational to prompt discussion.

**Process:**
1. `validate_phase` — parse phase number, grep ROADMAP.md for it, exit if not found
2. `analyze_phase` — surface assumptions across 5 fixed areas: Technical Approach,
   Implementation Order, Scope Boundaries, Risk Areas, Dependencies — each marked "Fairly
   confident" / "Assuming" / "Unclear"
3. `present_assumptions` — dump formatted assumptions, ask "What do you think?", wait
4. `gather_feedback` — acknowledge corrections or confirm
5. `offer_next` — presents a menu: run full `discuss` mode, run `plan-phase`, re-examine, or stop

**No agent spawned.** No CONTEXT.md, no DISCUSSION-LOG.md, no git commit, no STATE.md update.
Pure conversation — a scratch pad for the user to sanity-check Claude's read of the phase before
committing to either real discuss-phase mode.

## Decision Guide

| Situation | Recommendation |
|---|---|
| First time touching a phase, no strong opinions yet | `discuss` (default) — full interview |
| Codebase already has strong conventions to infer from | `discuss_mode: assumptions` — fewer questions, evidence-backed |
| Want a fast sanity check before committing to either | `--assumptions` flag — no artifacts, pure conversation |
| User profile is `opinionated`/decisive | `assumptions` mode's `minimal_decisive` tier fits naturally |
| User profile is `conservative`/exploratory | `discuss` mode, or `assumptions` mode's `full_maturity` tier |

## References

- Mode routing: `commands/gsd/discuss-phase.md:47-67`
- Interview workflow: `gsd-core/workflows/discuss-phase.md`
- Assumptions workflow: `gsd-core/workflows/discuss-phase-assumptions.md`
- Flag-only assumptions preview: `gsd-core/workflows/list-phase-assumptions.md`
- Analyzer agent: `agents/gsd-assumptions-analyzer.md`
- Config default: `gsd-core/bin/shared/config-defaults.manifest.json:42`
- Config schema description: `gsd-core/references/planning-config.md:271`
