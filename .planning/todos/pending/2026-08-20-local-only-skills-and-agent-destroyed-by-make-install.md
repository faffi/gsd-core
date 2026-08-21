---
created: 2026-08-20T23:40:00.000Z
title: Two local-only skills and one agent are destroyed by make install
area: tooling
severity: blocker
files:
  - bin/install.js:10820-10829 (the stale-skills wipe — readdir skills/, rmSync every dir starting with "gsd-")
  - skills/gsd-review-concurrent/ (DOES NOT EXIST HERE — the real home; 217 lines, referenced by port concern 4.8)
  - skills/gsd-graph/ (DOES NOT EXIST HERE — the real home; 108 lines)
  - agents/gsd-prd-reviewer.md (DOES NOT EXIST HERE — the real home; 41 lines)
  - .planning/runbooks/local-only-artifacts/ (rescued copies + README — STOPGAP, not the fix)
  - .planning/runbooks/fork-install-and-update.md (documents `make install` — needs the warning until this is fixed)
  - .planning/todos/pending/2026-08-20-port-4-8-convergence-max-cycles-and-concurrent-routing.md (blocked by this)
---

## Problem

Three GSD artifacts exist **only** in the installed `~/.claude` tree — absent from this repo,
from its entire history, and from the pristine 1.10.0 baseline:

| Artifact | Lines | Authored |
|---|---|---|
| `~/.claude/skills/gsd-review-concurrent/SKILL.md` | 217 | 2026-08-12 |
| `~/.claude/skills/gsd-graph/SKILL.md` | 108 | 2026-08-17 |
| `~/.claude/agents/gsd-prd-reviewer.md` | 41 | 2026-08-12 |

**`make install` destroys all three.** `bin/install.js:10820-10829` reads `<targetDir>/skills`,
filters to directories whose name starts with `gsd-`, and `rmSync`s each one — then replaces
them *from this repo*. A `gsd-*` artifact with no counterpart in the repo is deleted and never
restored. The agent path behaves the same way.

## Validation verdict — 2026-08-20, PROVEN BY EXECUTION

Tested in `/tmp/gsd-skilltest` via `--config-dir`, never touching `~/.claude`:

```
install 1 → 71 gsd-* skills installed
plant gsd-review-concurrent, gsd-graph, gsd-dev-preferences, gsd-prd-reviewer
install 2 → DESTROYED gsd-review-concurrent
            DESTROYED gsd-graph
            DESTROYED gsd-prd-reviewer.md
            SURVIVED  gsd-dev-preferences   ← has explicit migration handling at :10810-10816
```

Reproduced across two independent runs. `gsd-dev-preferences` survives **only** because the
installer carries a named special case for it; that is not a general protection.

The installer reports `✓ Installed 72 skills to skills/` and exits 0. **Nothing in its output
names what it removed** — same failure class as the rest of this campaign: it reports success
while silently destroying work.

## Why the local-patch analysis missed this entirely

`~/.claude/scripts/gsd-local-patches-1.10.0.diff` — the basis for the whole
`porting-local-patches-to-the-fork.md` campaign — was scoped to **`~/.claude/gsd-core/`**.
`skills/` and `agents/` are **siblings** of `gsd-core/`, not children. No amount of rigour
inside that diff could have surfaced these.

The diff *does* mention `gsd-review-concurrent` three times (lines 822, 831, 834) — but only
as the **routing target** of port concern 4.8. Concern 4.8's own validation said "bring the
skill onto the same branch; it is a single self-contained SKILL.md" while assuming it existed
in-repo. **It does not.** 4.8's routing half therefore requires importing a whole new skill,
not referencing an existing one.

## Solution

**Robust fix — put each file in its real home on a `local/*` branch:**

```
skills/gsd-review-concurrent/SKILL.md
skills/gsd-graph/SKILL.md
agents/gsd-prd-reviewer.md
```

Once in the repo, `bin/install.js`'s wipe-then-replace becomes replace-**from-source** and all
three survive every install permanently — the identical mechanism protecting the other 71
skills. This is the root-cause fix, not a workaround, and it needs no installer change.

Then delete `.planning/runbooks/local-only-artifacts/`, whose only purpose is to stop the
content being lost before this lands.

**Do NOT** patch `install.js` to skip unknown `gsd-*` dirs — wipe-then-replace-from-source is
correct behaviour; the defect is that these three were never put in the source.

**Interim:** do not run `make install` until this lands, or the rescued copies are the only
surviving version.

## Open question for the operator

`gsd-graph` and `gsd-prd-reviewer` were never analysed for effectiveness/robustness the way
the ten port concerns were — they were invisible to the diff. Decide whether they get the same
validation treatment before promotion, or go in as-is on the grounds that they are already in
daily use.

## Cross-references

- Rescued copies + provenance: `.planning/runbooks/local-only-artifacts/README.md`
- Blocks the routing half of: port concern 4.8 todo
- Campaign context: `.planning/runbooks/porting-local-patches-to-the-fork.md` §4.8, §4c
