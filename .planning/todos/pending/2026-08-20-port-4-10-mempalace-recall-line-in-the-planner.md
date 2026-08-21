---
created: 2026-08-20T23:19:00.000Z
title: Port 4.10 — mempalace recall line in the planner (the only item that survived validation unchanged)
area: tooling
severity: minor
files:
  - agents/gsd-planner.md (+1 line — cat "$phase_dir"/*MEMORY-RECALL.md)
  - agents/gsd-planner.md:614 ($phase_dir binding — "Extract from init JSON")
  - capabilities/mempalace/capability.json:96-109 (the declared plan:pre producer)
  - skills/gsd-mempalace-recall/SKILL.md (step 4 — "The planner consumes it.")
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.10 — full analysis)
---

## Problem

`mempalace-recall` writes `MEMORY-RECALL.md` at `plan:pre` and nothing reads it. The patch adds
one line — `cat "$phase_dir"/*MEMORY-RECALL.md` — so the planner picks it up.

## Validation verdict — 2026-08-20

**PORT AS-IS. The only item in the set that survived validation unchanged, and the
strongest-founded of the ten.**

- **The producer is real and traceable**, unlike 4.1's. `capabilities/mempalace/capability.json:96-109`
  formally declares a `plan:pre` step: `{"ref":{"skill":"mempalace-recall"},
  "produces":["MEMORY-RECALL.md"],"when":"mempalace.enabled","onError":"skip"}`, and
  `skills/gsd-mempalace-recall/SKILL.md` step 4 says *"Write `MEMORY-RECALL.md` in the current
  phase directory. The planner consumes it."* Reproduced live:
  `gsd-tools query loop.render-hooks plan:pre` on a scratch project with `mempalace.enabled: true`
  returns the step in `activeHooks`.
- **Three real artifacts on disk**, written 2026-08-18/19 under
  `~/gsd-workspaces/{security-vpc,bedrock-access,ctem-gitlab-group}/…/phases/76-*/MEMORY-RECALL.md`,
  well-formed and matching the skill's documented format. **Live production usage, not just spec.**
- **`$phase_dir` is NOT the `$FORGE` defect class.** It is bound by prose in an earlier step
  (`gsd-planner.md:614`), and the three **pre-existing** sibling lines in the same fence
  (`*-CONTEXT.md`, `*-RESEARCH.md`, `*-DISCOVERY.md`) already rely on the identical cross-fence
  binding. The new line is a 4th use of a shipped pattern — it cannot introduce a scoping bug its
  neighbours do not already have.
- **Inert by default:** `mempalace.enabled` defaults `false`, so out of the box the step never
  fires and the glob never matches. Contribution is real but scoped to projects that opt in.
- ⚠ **zsh caveat (minor, inherited).** Under zsh's default `NOMATCH`, a non-matching glob makes
  the *shell* abort and print `no matches found:` **before `cat` runs**, so `2>/dev/null` does not
  suppress it. Verified by direct execution. Does not fire in practice — Claude Code's Bash tool
  runs fences via `bash -c` — and all three sibling lines share it. Not introduced here.

## Solution

Runbook §5 item 2 — second, right after the 4.1 pilot, because it proves the `agents/` path
end-to-end at one line. Direct source, no translation.

**Upstream viability: strong.** One line, guarded, completes an existing capability's wiring.
**"Producer with no consumer" is confirmed:** a repo-wide `MEMORY-RECALL` grep at 1.11.0 finds
only the capability declaration, the producing skill, generated registry output and docs —
**zero** consumers in any agent or workflow. Arguably an upstream bug worth reporting as such.

## Cross-references

- Analysis: runbook §4.10 · sequence §5 item 2
