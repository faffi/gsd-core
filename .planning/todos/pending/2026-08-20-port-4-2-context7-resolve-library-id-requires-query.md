---
created: 2026-08-20T23:11:00.000Z
title: Port 4.2 — context7 resolve-library-id requires query as well as libraryName
area: tooling
resolves_phase: 6
severity: major
scope: Small
scope_note: 3 doc-only files, already validated against the live tool schema, splits cleanly into two commits, no runtime risk
files:
  - agents/gsd-advisor-researcher.md (stale libraryName-only call signature)
  - agents/gsd-executor.md (call signature + the mcp__plugin_context7_context7__* judgement call)
  - gsd-core/references/research-documentation-lookup.md (call signature + fallback conditions)
  - .planning/runbooks/porting-local-patches-to-the-fork.md (§4.2 — full analysis)
---

## Problem

Upstream documents `resolve-library-id` as taking `libraryName` only. **Verified against the
live tool schema** (not docs): its `required` array is `["query", "libraryName"]` — both are
genuinely required. A wrong call signature fails every documentation lookup.

The patch corrects the signature and expands the "context7 genuinely unavailable" fallback
conditions (user scope lives in `~/.claude.json`, etc.).

## Validation verdict — 2026-08-20

**Port. Doc-only, no build, no runtime risk.** Three stale `libraryName`-only sites remain at
1.11.0 and the patch covers all of them — a repo-wide grep finds no others.

- ⚠ **Three files, not four.** `gsd-core/workflows/discovery-phase.md` **does not exist at
  1.11.0** — deleted upstream in `c5b83cb0` (*"delete two unreachable workflows"*, #3560/#3564),
  confirmed an ancestor of `v1.11.0`. It was dead code; nothing referenced it. The patch predates
  the deletion (authored Aug 12, deleted Aug 15). **There is no successor** — `git log --follow`
  finds no rename. Drop it from scope; do not hunt for somewhere to re-anchor its hunk.
- ⚠ **Separate judgement call, do not port on autopilot.** `gsd-executor.md` also *drops*
  `mcp__plugin_context7_context7__*` from its availability check. That pattern is **live and
  current** in 1.11.0 — present in 8 other files (`gsd-domain-researcher`,
  `gsd-project-researcher`, `gsd-advisor-researcher`, `gsd-ui-researcher`,
  `gsd-phase-researcher`, `gsd-ai-researcher`, `gsd-planner`, `docs/AGENTS.md`). Not legacy cruft.
  - **Narrower than it looks:** the removal is from *body prose* only — the frontmatter `tools:`
    allowlist still grants it. The effect is a detection gap (the model may not think to look
    under that name), not a permissions gap.
  - **Settled:** the plugin is *installed but disabled* here
    (`~/.claude/settings.json:251` → `"context7@claude-plugins-official": false`, 1,574 historical
    uses). Live tools come from a separate user-scope HTTP entry at `~/.claude.json:4431`.
    Nothing in CI constrains it — `tests/context7-tool-name-parity.test.cjs` never references the
    plugin-scoped name. **Porting the prose removal is safe, but it is a preference, not a
    correctness fix.** Keep it in a separate commit from the API correction.

## Solution

Third in sequence (runbook §5). All three files are direct-source — `agents/` and
`gsd-core/references/` are tracked here, so **no `.cjs`→`.cts` translation is needed**.

Split into two commits: (1) the API signature correction — upstreamable; (2) the
`mcp__plugin_context7_context7__*` prose removal — local preference.

**Upstream viability: strong** for (1). Factual API correction, verifiable against the
context7 tool schema.

## SPEC cross-reference — 2026-08-25 (gsd-1.10.0-mods) — adds a genuinely new requirement (R2)

`~/Desktop/gsd-1.10.0-mods/SPEC-04-context7-lookup-correctness.md` scopes narrower than this todo
(2 files — `research-documentation-lookup.md` + `discovery-phase.md` — vs this todo's 3, which also
covers `agents/gsd-advisor-researcher.md` and `agents/gsd-executor.md` outside `gsd-core/`). **No
real conflict on `discovery-phase.md`**: the SPEC was derived against the installed **1.10.0** tree,
where that file still exists; this todo already established (independently, via `git log --follow`)
that it was deleted upstream between 1.10.0 and 1.11.0 (`c5b83cb0`, confirmed ancestor of
`v1.11.0`). Both are correct for their respective baselines — this todo's "drop it from scope" call
stands.

**R2 is new scope, not currently in this todo.** SPEC-04 identifies a second, independent defect in
the same file this todo already touches (`research-documentation-lookup.md`): a blanket claim that
"subagents cannot see a project's `.mcp.json`" is stated as universal when it only holds under three
narrower conditions. Failure mode is the dangerous kind — **silent**: an agent believing the
blanket claim falls back to a slower CLI/web path with no error, degrading doc quality invisibly
(vs R1's failure, which is a loud `InputValidationError` — easy to catch by contrast). Add to this
todo's scope:

- Remove the blanket subagent-visibility claim; replace with the three verified conditions plus the
  wildcard-grant exception
- Carry a verification date inline (SPEC-04 recorded 2026-08-12) — this is a claim about third-party
  runtime behavior and will go stale; **re-verify at implementation time**, don't port the text on
  faith
- Per this repo's own context7-verification rule (`~/.claude/rules/review-agents-verify-tech-claims-with-context7.md`)
  and CLAUDE.md's third-party-docs rule: confirm the current `resolve-library-id` `required` array
  via `ToolSearch("select:mcp__context7__resolve-library-id")` before finalizing R1's text too — the
  schema may have changed since 2026-08-12.

## Cross-references

- Analysis: `.planning/runbooks/porting-local-patches-to-the-fork.md` §4.2 · sequence §5 item 3
- SPEC (adds R2): `~/Desktop/gsd-1.10.0-mods/SPEC-04-context7-lookup-correctness.md`
