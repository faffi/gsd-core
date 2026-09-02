# Capability Steps

> **Generated:** 2026-09-01T00:00:00Z
> **GSD version:** 1.11.0-237-g29c5ec373
> **Source:** `docs/reference/capability-manifest.md`, `docs/adr/894-capability-declaration-format.md`, `gsd-core/bin/lib/capability-validator.cjs`, `gsd-core/bin/lib/loop-resolver.cjs`, `gsd-core/references/loop-hook-dispatch.md`, `docs/how-to/develop-a-capability.md`, `capabilities/*/capability.json`

<purpose>
Reference documentation for the `step` hook kind within GSD's capability manifest system —
schema, validation rules, dispatch mechanics (skill/agent/command), the produces/consumes
contract, and real production examples. Complements `gsd-lifecycle-events.md` (which documents
hooks generically across all three kinds) with a kind-specific deep dive.
</purpose>

## Where Steps Fit

A capability's manifest declares hooks of three kinds at the 12 fixed **Loop Extension Points**
(see `gsd-lifecycle-diagram.md`): `contribution`, `gate`, and `step`.

| Kind | Purpose | Can block the workflow? |
|------|---------|--------------------------|
| `contribution` | Inject a fragment into a role's context | No |
| `gate` | Evaluate a blocking or advisory check | Yes, if `blocking: true` |
| **`step`** | **Dispatch a skill, agent, or subprocess command** | **No — steps are purely additive** |

This doc covers `step` only.

## Schema

From `docs/reference/capability-manifest.md:76-84` and the ground-truth validator
(`gsd-core/bin/lib/capability-validator.cjs:2788-2870`, function `validateStep`):

| Field | Type | Required | Validation |
|---|---|---|---|
| `point` | string | Yes | Must be one of the 12 closed `VALID_LOOP_POINTS` identifiers |
| `ref` | object | Yes | Exactly one of `{skill}`, `{agent}`, `{command}` — zero or ≥2 keys is a validation error (`:2801-2807`) |
| `ref.skill` | string | conditional | Must NOT start with `gsd-` (double-prefix guard — dispatch prepends `gsd-` at runtime, `:2810-2818`); must appear in this capability's own `skills[]` (`:2819-2826`) |
| `ref.agent` | string | conditional | Must appear in this capability's own `agents[]` (`:2827-2835`) |
| `ref.command` | string | conditional | Only type-checked (`typeof === 'string'`) at schema time (`:2836-2838`) — no allowlist check here; the injection defense is pushed to dispatch time (see below) |
| `produces` | string[] | Yes | Array of artifact names. Use `[]` if it produces nothing — an *omitted* key fails validation, an *empty array* does not |
| `consumes` | string[] | Yes | Same shape as `produces` |
| `onError` | `"skip"` \| `"halt"` | Yes | Must be present and exactly one of these two values (`:2865-2867`) |
| `when` | string | No | Dotted config key gating activation; must be a string if present (`:2857-2859`) |
| `fragment` | object | No | `{path}` or `{inline}` — **legal on `step`, not just `contribution`**, and used in production (see Examples) |

## Dispatch: Three Mechanisms, Not Two

The canonical, point-agnostic dispatch contract lives in `gsd-core/references/loop-hook-dispatch.md`
— every host workflow that reads `loop render-hooks <point> --raw` defers to it rather than
reimplementing dispatch per-workflow.

### `ref.skill` → Skill tool

Dispatched as `gsd-<ref.skill>` — the `gsd-` prefix is applied exactly once, at dispatch time,
never present in the manifest. This is why the validator rejects a manifest value that already
starts with `gsd-`: it would double-prefix to `gsd-gsd-<x>` at dispatch.

### `ref.agent` → Agent tool

Dispatched with `subagent_type = ref.agent`. The workflow must print a liveness banner first
(*"◆ Spawning `<agent>`... (runs in a subagent — no output until it returns; expected, not a
freeze)"*) so a silent-but-healthy agent isn't mistaken for a hang.

### `ref.command` → subprocess, not a tool call at all

`ref.command` is a real, shipped mechanism — not theoretical. It dispatches as a `gsd_run`
subprocess invocation: `gsd_run ${ref.command} --phase "${PHASE_NUMBER}" --raw`. Two production
capabilities use it today:

- `capabilities/intel/capability.json` — `ref.command: "intel api-surface"`
- `capabilities/refactor-trigger/capability.json` — `ref.command: "refactor evaluate"`

**Security note — `ref.command` is third-party manifest input that can reach a shell.**
`loop-hook-dispatch.md:45-58` requires validating it **in-context**, against
`^[a-z][a-z0-9-]*( [a-z][a-z0-9-]*)*$`, **before** any shell use — explicitly never by pasting it
into a shell command to test it there, because a value carrying a quote, `;`, backtick, `$(`, or
newline would terminate the variable assignment and execute as its own statement before a
shell-side check could ever fire. A value that fails this pattern is treated as a malformed
manifest: warn, skip, continue — it must never halt the whole workflow. The identical requirement
applies to a `gate`'s `check.predicate`, passed as a single argv element and never re-quoted into
a shell string (`:80-84`). `execute-phase.md:1028` and `verify-work.md:80` both carry an explicit
`⚠` inline warning pointing back to this section — treated as load-bearing, not a footnote.

### What the registry itself does (and doesn't do)

`loop-resolver.cjs`'s `renderLoopHooks` renders only a **descriptive markdown label** per active
hook (e.g. `skill:ui-review (ui)` or `agent:gsd-pattern-mapper (pattern-mapper)`) — it does not
perform the Skill/Agent/subprocess call itself. The actual tool call is issued by whichever host
workflow reads the `--raw` JSON `activeHooks` array and follows `loop-hook-dispatch.md`.

## produces/consumes Contract and the Uniqueness Invariant

**Rule** (`capability-manifest.md:80,310`; ADR-894 §4, Decision #6): no two capability steps may
`produces` the same artifact at the same Loop Extension Point — this would make data-flow
resolution ambiguous and is rejected at **generation time**, not at runtime.

**Enforcement mechanism** (`capability-validator.cjs:3086-3117`):

1. Build `capHookProducers[artifact] = [{pointIdx, capId, stepIdx}, ...]` across every
   feature-role capability's steps.
2. Group by `pointIdx`, then count **distinct `(capId, stepIdx)` pairs** — not raw list entries.
   This distinction matters: a single step listing the same artifact twice within its own
   `produces` array does *not* false-positive, because it's only one producer step (`:3100-3103`).
3. ≥2 distinct producer steps at the same point → build fails with a named error identifying the
   artifact, the point, and the colliding capability ids (`:3108-3114`).

**Self-consume rule** (`:3119-3129`): a step cannot satisfy its own `consumes[A]` from its own
`produces[A]`. `A` must come from a host artifact produced at or before this step's point, or
from a *different* capability/step's `produces` at or before this point — "different" meaning
`capId != H.capId OR stepIdx != H.stepIdx`.

**Ordering**: within one point, steps are topologically sorted by the produces/consumes graph,
with capability id as tiebreak (`capability-manifest.md:74`; `capability-validator.cjs:3570`,
`topoSortSteps` → generic `topoSortHookEntries(entries, 'step', 'steps')`). The generator bakes
this order into `byLoopPoint` at build time; `loop.render-hooks` only filters to the currently
*active* subset at runtime — it does not re-sort (ADR-894 §5).

## Validation Error Messages (Verbatim)

| Condition | Message |
|---|---|
| `ref` has 0 keys | `"<prefix>.ref must have a \"skill\", \"agent\", or \"command\" key"` |
| `ref` has ≥2 keys | `"<prefix>.ref must have exactly one of \"skill\", \"agent\", or \"command\", not multiple"` |
| `ref.skill` starts with `gsd-` | `"<prefix>.ref.skill \"<x>\" must not start with \"gsd-\" (it is an unprefixed stem; the workflow prepends \"gsd-\" at dispatch — starting with \"gsd-\" would produce \"gsd-<x>\")"` |
| `ref.skill`/`ref.agent` not owned by this capability | `"<prefix>.ref.skill \"<x>\" is not declared in this capability's skills: [...]"` (same shape for `.ref.agent`/`agents`) |
| Duplicate producer (build-time, cross-capability) | `"duplicate-producer invariant violated: artifact \"<A>\" is produced by two or more capability steps at the same Loop Extension Point \"<point>\" (capabilities: <ids>). ... makes data-flow resolution ambiguous and is rejected at gen time."` |
| Point doesn't dispatch this kind | `"capability \"<id>\" steps[N].point \"<point>\" registers a step hook, but the host call site's dispatch text never covers kind == \"step\" (it covers: gate). A hand-rolled single-kind consumer silently never dispatches the other kinds — dispatch every registered kind per gsd-core/references/loop-hook-dispatch.md."` (from `docs/how-to/develop-a-capability.md:130-135`, shown as real generator output against a demo manifest) |

## Real Examples

Verified live from `capabilities/*/capability.json` — verbatim, not paraphrased.

### `security` — skill ref, `onError: halt`

```json
{
  "point": "verify:post",
  "ref": { "skill": "secure-phase" },
  "produces": ["SECURITY.md"],
  "consumes": ["SUMMARY.md"],
  "when": "workflow.security_enforcement",
  "onError": "halt"
}
```

### `intel` — command ref (proof `ref.command` ships in production)

```json
{
  "point": "plan:pre",
  "ref": { "command": "intel api-surface" },
  "produces": [".planning/intel/API-SURFACE.md"],
  "consumes": [],
  "when": "intel.enabled",
  "onError": "skip"
}
```

### `mempalace` — richest example: 5 steps, mixes skill + agent refs across 5 points

```json
[
  { "point": "discuss:post", "ref": {"skill": "mempalace-capture"}, "produces": [], "consumes": ["CONTEXT.md"], "when": "mempalace.enabled", "onError": "skip" },
  { "point": "plan:pre",     "ref": {"skill": "mempalace-recall"},  "produces": ["MEMORY-RECALL.md"], "consumes": ["CONTEXT.md"], "when": "mempalace.enabled", "onError": "skip" },
  { "point": "plan:post",    "ref": {"skill": "mempalace-capture"}, "produces": [], "consumes": ["PLAN.md"], "when": "mempalace.enabled", "onError": "skip" },
  { "point": "verify:post",  "ref": {"skill": "mempalace-capture"}, "produces": [], "consumes": ["SUMMARY.md"], "when": "mempalace.enabled", "onError": "skip" },
  { "point": "ship:post",    "ref": {"agent": "gsd-mempalace-curator"}, "produces": [], "consumes": ["UAT.md"], "when": "mempalace.enabled", "onError": "skip" }
]
```

Three of these five steps declare `produces: []` — a step doesn't have to produce a file at all;
it can be pure side-effect (writing to an external memory store) gated only by `consumes` +
`when`.

### Full enumeration — every capability declaring ≥1 step (11 total)

`ai-integration` (1) · `code-review` (1) · `intel` (1) · `live-dom-uat` (1) · `mempalace` (5) ·
`nyquist` (1) · `pattern-mapper` (1) · `refactor-trigger` (1) · `research` (1) · `security` (1) ·
`ui` (2)

`pattern-mapper` and `research` both attach a `fragment.path` to their step — confirming
`fragment` on `step` is a production feature, not a schema-only allowance.

## Non-Obvious Findings

1. **Steps cannot block — this is load-bearing, not incidental.** Asserted independently in
   three places: ADR-894's clarification resolving #1022, `capability-manifest.md:82`
   ("Steps are purely additive"), and `loop-hook-dispatch.md` ("advisory by construction"). This
   is *why* `ui`'s `plan:pre` step (which self-skips on non-frontend phases) is paired with a
   separate blocking **gate** at `execute:wave:post` — the step alone cannot enforce anything; a
   failed step just gets `onError` treatment (skip, or halt-with-warning), never a workflow
   redirect.

2. **Point support for a kind is generated, not merely asserted in docs.**
   `gen-capability-registry.cjs`'s `getWiredKinds()` scans the actual host workflow's dispatch
   prose and rejects a manifest that declares a kind at a point the workflow's text doesn't
   handle. This closed a real, shipped bug class (#3866): `verify:pre` used to dispatch only
   `gate`, so a `step` registered there was silently dead. It is now a **build-time reject**,
   never a silent runtime no-op.

3. **`execute:task` is deliberately NOT a 13th Loop Extension Point.** It's documented in
   `loop-hook-dispatch.md`'s final section as a structurally different, harder-guaranteed
   mechanism (`taskContentResolver` in the manifest body, dispatched by a direct required
   subprocess call with a binding exit code) — precisely *because* the 12-point step/gate system
   is "best-effort prose dispatch" that a hard-halt safety property cannot be built on top of. A
   missed dispatch there would be indistinguishable from a legitimate empty-resolver fallback.
   Do not conflate it with `step`/`gate` — it's the seam those two kinds are explicitly excluded
   from.

4. **The duplicate-producer check is smarter than "no repeated string."** It counts distinct
   `(capId, stepIdx)` pairs, specifically so a single step listing the same artifact twice in its
   own `produces` array doesn't false-positive as two competing producers.

5. **`declaredSkills`/`declaredAgents` ownership checks can be `null`-disabled**
   (`capability-validator.cjs:2819,2829` guard with `!== null`), implying at least one caller path
   validates `ref` shape without the ownership check. Which caller, and why, was not traced —
   flagged here as unconfirmed rather than asserted.

## References

- Manifest schema: `docs/reference/capability-manifest.md`
- Design rationale: `docs/adr/894-capability-declaration-format.md`
- Validator: `gsd-core/bin/lib/capability-validator.cjs:2788-2870` (`validateStep`),
  `:3050-3129` (duplicate-producer + self-consume invariants), `:3570` (`topoSortSteps`)
- Registry rendering: `gsd-core/bin/lib/loop-resolver.cjs` (`renderLoopHooks`)
- Dispatch contract (all hosts defer to this): `gsd-core/references/loop-hook-dispatch.md`
- Worked authoring example: `docs/how-to/develop-a-capability.md:50-199`
- Generic hook-point documentation (all 3 kinds): `.planning/reference/gsd-lifecycle-events.md`,
  `.planning/reference/gsd-lifecycle-diagram.md`
