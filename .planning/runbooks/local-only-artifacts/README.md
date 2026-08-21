# Local-only artifacts — rescued 2026-08-20

Three GSD artifacts exist **only** in the installed `~/.claude` tree. They are not in this
repo, not in this repo's history, and not in the pristine 1.10.0 baseline. **`make install`
destroys all three** — proven by execution, see the todo below.

| Rescued copy | Real home | Lines | Authored |
|---|---|---|---|
| `skills--gsd-review-concurrent--SKILL.md` | `skills/gsd-review-concurrent/SKILL.md` | 217 | 2026-08-12 |
| `skills--gsd-graph--SKILL.md` | `skills/gsd-graph/SKILL.md` | 108 | 2026-08-17 |
| `agents--gsd-prd-reviewer.md` | `agents/gsd-prd-reviewer.md` | 41 | 2026-08-12 |

Filenames encode the destination path with `--` for `/`, so the real home is never guessed.

## ⚠ This directory is a STOPGAP, not the fix

These copies stop the content being lost. They do **not** stop the install destroying the
live ones, and nothing loads a skill from `.planning/`. **The actual fix is to put each file
in its real home on a `local/*` branch**, at which point `bin/install.js`'s wipe-then-replace
becomes replace-*from-source* and they survive every install permanently — the same mechanism
that protects the other 71 skills.

Delete this directory once that lands. Until then, do not treat a green `make install` as
evidence the skills are safe.

## Why the local-patch analysis missed them

`~/.claude/scripts/gsd-local-patches-1.10.0.diff` was scoped to **`~/.claude/gsd-core/`**.
`skills/` and `agents/` are siblings of `gsd-core/`, not children — so no amount of care
inside that diff could have surfaced these. The diff does mention `gsd-review-concurrent`
three times (lines 822, 831, 834), but only as the *routing target* of concern 4.8; it never
carries the skill's content.

## Tracked by

`.planning/todos/pending/2026-08-20-local-only-skills-and-agent-destroyed-by-make-install.md`
