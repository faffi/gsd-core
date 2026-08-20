---
created: 2026-08-20
title: Intel capability — end-to-end lifecycle trace
area: capability/intel
kind: research
traced_against: working @ 71addddf (v1.11.0)
status: findings-not-independently-reverified
surfaces_defects:
  - "plan-phase.md §7.8 bypass drops the API-surface hint on every replan cycle after the first"
  - "intel patch-meta / extract-exports ignore intel.enabled and write regardless"
---

> **Provenance.** Produced by a separate tracing session against `working @ 71addddf`
> (v1.11.0) and filed here verbatim below the rule. Its claims were verified *by that
> session* — live probes, file:line citations, and one explicitly-labelled
> inspection-only finding (the §7.8 bypass). They have **not** been independently
> re-verified during filing. Re-check any line number before acting on it: this repo's
> `gsd-core/` is wipe-replaced on every GSD update, and `src/*.cts` moves with upstream.
>
> Two actionable defects are called out in the frontmatter above. Neither is captured as
> a todo yet.

---

Traced end-to-end on `working` @ `71addddf` (v1.11.0). `git diff next working` on every intel path is empty, so this is upstream behaviour, not your fork's.

## What it is

A **code-intelligence store**: five JSON files under `.planning/intel/` that agents query instead of re-reading the codebase.

| File                    | Holds                                   |
| ----------------------- | --------------------------------------- |
| `stack.json`            | tech stack                              |
| `file-roles.json`       | file graph + real exported symbol names |
| `api-map.json`          | API surfaces                            |
| `dependency-graph.json` | dependency chains                       |
| `arch-decisions.json`   | architecture summary (JSON, not prose)  |

Defined at `src/intel.cts:29-35`. Nine subcommands routed by `src/intel-command-router.cts:109`.

## The structural fact everything else follows from

**The CLI cannot populate the store.** `intelUpdate` (`src/intel.cts:307-314`) is a stub:

```
{ "action": "spawn_agent",
  "message": "Run gsd-tools intel update or spawn gsd-intel-updater agent for full refresh" }
```

That message is circular — running `intel update` tells you to run `intel update`. The five JSON files are written only by the `gsd-intel-updater` LLM agent, and per the repo's own `gsd-core/references/agent-contracts.md:43`, "no `*.md` workflow currently spawns this agent."

I confirmed the consequence rather than inferring it. Fresh project, `intel.enabled: true`, run the `plan:pre` step:

```
{ "written": "…/.planning/intel/API-SURFACE.md", "symbolCount": 0, "stale": true }
```
```markdown
> **Incomplete:** api-map.json has no entries (intel extraction is regex/JS-only or not yet populated).
> Treat absence here as "unknown", not "does not exist".
```

`★ Insight ─────────────────────────────────────`
`intelApiSurface` **always** writes the file, even with zero symbols. Skipping the write on empty would leave a stale surface from a prior run that reads as authoritative. Writing an explicitly-empty file with an "absence means unknown" banner is fail-loud design — the same instinct as `Optional<T>` over `null`.
`─────────────────────────────────────────────────`

Extraction is regex-only and JS/CJS/ESM-only (`src/intel.cts:578-685` — `module.exports`, `exports.X`, `export function/const/class/{}`). No Python, Go, or Rust. That's why every consumer is worded as a *hint*.

## Where it plugs into the lifecycle

GSD has 12 canonical loop points (`src/loop-resolver.cts:73-85`). Intel declares exactly one step — `plan:pre` → `intel api-surface` — but it actually reaches the lifecycle in **three** places, only one of which is declared.

**1. Declared: `plan:pre`.** Verified live, not read off the manifest:

```
intel.enabled=false → capIds: [ai-integration, research, ui, pattern-mapper, …]   intel present: False
intel.enabled=true  → capIds: [ai-integration, intel, research, ui, …]            intel present: True
```

The `when: "intel.enabled"` gate is evaluated by the registry, not by workflow prose.

Dispatch is the subtle part. The step uses `ref.command`, and the **generic** dispatcher at `gsd-core/workflows/plan-phase.md:459` handles only `ref.skill` and `ref.agent` — a `ref.command` falls straight through it. Intel survives because `plan-phase.md:650-665` (§7.9, "Regenerate API-SURFACE.md") matches the hook by `capId == "intel"` and runs a *hardcoded* `gsd_run intel api-surface`, then hands `API_SURFACE_PATH` to the planner at step 8 as a HINT-ONLY input.

**2. Undeclared: it silently promotes the plan drift guard.** `getEffectiveAuthority` (`src/plan-drift-guard.cts:90-95`) auto-upgrades the symbol-verification resolver from `grep` to `intel` whenever intel is enabled. Confirmed:

```
intel.enabled=false → drift-guard authority → grep
intel.enabled=true  → drift-guard authority → intel
```

This appears nowhere in `capabilities/intel/capability.json`. Flipping one flag swaps plan review from grepping live source to consulting a possibly-empty JSON index — at a nominally *higher* authority rung (`grep:0`, `intel:1`). Blast radius is bounded: both rungs sit below the hard-block threshold of 3, so a MISSING symbol stays `needs-acknowledgement` either way. It degrades signal, it can't block you.

**3. Manual: `/gsd-map-codebase --query`.** The command file says "run the intel workflow" (`commands/gsd/map-codebase.md:38`) — **there is no intel workflow.** `find gsd-core -name "*intel*"` returns only the two `bin/lib` modules. Dangling referent.

## A defect the trace surfaced

§7.9 is reachable on every planning host (`autonomous.md` and `plan-review-convergence.md` both delegate via `Skill(skill="gsd-plan-phase")`), but §7.8 has two jumps that land on **step 8**, hopping over it:

- `plan-phase.md:613` — "If PATTERNS.md already exists … Skip to step 8"
- `plan-phase.md:607` — "or Step 8 if pattern mapper is disabled"

`API_SURFACE_PATH` is assigned *only* at `:661` inside §7.9, and `:728` wraps the entire `<intel_surface_hint>` block in `${API_SURFACE_PATH ? …}`. So on either bypass the hint vanishes from the planner prompt with no warning. `PATTERNS.md` exists from cycle 1 of `/gsd-plan-review-convergence`, meaning **every replan cycle after the first drops the API-surface hint** — in the very workflow that is intel's strongest consumer. Found by inspection, not execution.

## Gating asymmetry

7 of 9 subcommands honour `intel.enabled`; `extract-exports` and `patch-meta` don't — the gate lives inside each function, not in the router. With `{"intel":{"enabled":false}}`:

```
status       → { "disabled": true, … }
patch-meta   → { "patched": true, "file": "…/api-map.json", "timestamp": "…" }   ← wrote anyway
```

Deliberate (`src/intel.cts:534`, `:575` — the updater agent needs both while populating), but it means `patch-meta` is a live JSON-timestamp writer on any `path.resolve(cwd, …)` target regardless of activation state.

## Two caveats on method

- Probes ran through the shipped `gsd-core/bin/lib` while I cite `src/*.cts`. I diffed intel's own subcommand array across both — identical.
- `tests/intel.test.cjs`: 813 pass, 8 fail. All 8 are the CLI-shelling block, failing in `tests/helpers.cjs:138` because the shipped `runtime-homes.cjs` lacks `NON_REGISTRY_CONFIG_HOME_DESCRIPTORS` that `src/runtime-homes.cts:526` exports. That's a stale built lib on this checkout — the helper's own error message names `npm run build:lib` as the remedy. Not an intel defect. I didn't rebuild, since that writes tracked files on `working` without you asking.

## One correction to your own notes

`~/.claude/reference/gsd-knowledge-capability-reference.md` §6 claimed intel's step "is a `ref.command`, which NO shipped workflow dispatches … run it manually after each refresh." That generalised a true statement about the *generic* contract into a false one about intel — §7.9 existed at v1.10.0 too, so it was wrong when written, not merely stale. I've patched §6 and the §0 table with the correction, the §7.8 bypass, the gating asymmetry, and pinned line numbers; the residual true case is `refactor-trigger`'s `refactor evaluate` at `execute:post` (zero handlers, and opt-in-off by default anyway). The header banner now marks §6 and §4's auto-upgrade as verified against 1.11.0 so the next reader doesn't redo this.

**Bottom line:** intel is a *lifecycle-wired but self-empty* capability. The plumbing works — the gate resolves, the hook fires, the surface renders, the drift guard upgrades. What's missing is a populator: enabling it costs you a recurring LLM-agent run you must remember to trigger yourself, or the whole chain runs correctly over an empty index. ADR-22 (`docs/adr/22-plan-drift-guard.md:37`) names the exit criteria for flipping the default: deterministic population, auto-refresh on staleness, multi-language coverage.