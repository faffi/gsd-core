---
created: 2026-08-20T23:11:00.000Z
title: Port 4.2 — context7 resolve-library-id requires query as well as libraryName
area: tooling
severity: major
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

## Cross-references

- Analysis: `.planning/runbooks/porting-local-patches-to-the-fork.md` §4.2 · sequence §5 item 3
