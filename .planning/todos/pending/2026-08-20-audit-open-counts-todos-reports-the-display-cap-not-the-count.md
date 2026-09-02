---
created: 2026-08-20T21:45:00.000Z
title: audit-open counts.todos reports the display cap, not the count
area: tooling
resolves_phase: 6
severity: major
scope: Small
scope_note: Recommended fix (option 1, count before slicing) mirrors an existing in-file pattern (scanContextQuestions) — one function, small diff
files:
  - src/audit.cts:743 (scanTodos — openFiles.slice(0, 5), the display cap)
  - src/audit.cts:758-760 (pushes the _remainder_count sentinel row)
  - src/audit.cts:1269-1270 (countReal — excludes _remainder_count from the count)
  - src/audit.cts:1276 (todos: countReal(todos.items))
  - src/audit.cts:71 (TodoItem._remainder_count — the only item type carrying it)
  - src/audit.cts:1130-1131 (scanContextQuestions — the CORRECT pattern, in the same file)
  - src/audit.cts:1402-1413 (the human renderer, which handles the cap correctly)
---

## Problem

`gsd-tools audit-open --json` emits a `counts` object. Every field in it is a real
count **except `todos`**, which reports `min(actual, 5)` — the display cap — with no
indication in `counts` that it was truncated.

```
counts.todos      = 5      ← what a consumer reads
_remainder_count  = 28     ← buried in items.todos as a sentinel row
list-todos count  = 33     ← the truth
files in pending  = 33
```

Measured on `~/gsd-workspaces/bedrock-access/bootstrap-terraform` at v1.11.0.

The mechanism, all in `src/audit.cts`:

```ts
:743   const displayFiles = openFiles.slice(0, 5);          // display cap
:758   if (openFiles.length > 5) {
:759     results.push({ _remainder_count: openFiles.length - 5, filename:'', … });
:1269  const countReal = (arr) => arr.filter(i => !i.scan_error && !i._remainder_count).length;
:1276  todos: countReal(todos.items),
```

`countReal` excludes the remainder sentinel — correctly, since it is not an item — but
the five surviving rows are all that is left after the slice, so the count inherits the
cap. `counts.total` (`:1284`) sums these, so it is understated by the same amount.

**Not a rendering bug.** The human report handles it properly (`:1402-1413` prints
`... and N more`). The defect is confined to the JSON contract, where a field named
`counts.todos` is not the count of todos.

## Why it matters

Silent wrong number in a machine-readable field — the same failure class as the
pause-work dead gate and the inert `$FORGE` guards: it does not error, it returns a
plausible value. A dashboard reading `counts.todos` renders **TODOS 5** against 33 real
todos and looks correct.

**Surfaced by a downstream consumer**, a session building `gsd-pane` (a read-only tmux
TUI shelling out to gsd-tools for Threads/Seeds/Todos/Backlog counts). They hit it while
validating my own incorrect advice to source todo counts from `audit-open`. Independently
reproduced here at v1.11.0; they measured it at 1.10.0, so it is not a recent regression.

## Todos is the only category affected

Grepped every cap in the file. `slice(0, 5)` at `:743` is the sole *item-list* cap, and
`_remainder_count` exists only on `TodoItem` (`:71`). All eight other scanners return
complete lists, so their counts are honest. That isolation is what makes it easy to miss:
a consumer that spot-checks `seeds` or `quick_tasks` sees correct numbers and generalises.

## The fix pattern already exists in the same file

`scanContextQuestions` truncates for display too, and gets it right:

```ts
:1130  question_count: questions.length,             // TRUE count, preserved
:1131  questions: questions.slice(0, 3).map(…),      // display only
```

The true count lives in a sibling field; no sentinel, no reconstruction. `scanTodos`
instead folds the cap into the count and leaves the truth recoverable only by summing
a sentinel row out of `items`.

Options, cheapest first:

1. **Count before slicing** — have `scanTodos` return `openFiles.length` for the count
   while still capping `items`. Smallest diff; `counts.todos` becomes honest and
   `_remainder_count` keeps working for the renderer.
2. **Mirror `question_count`** — add `todo_count` alongside, leave `counts.todos` alone.
   Backwards-compatible but entrenches the misleading field.
3. **Document it** — state in the contract that `counts.todos` is display-capped and that
   consumers must add `_remainder_count`. Cheapest, but every new consumer pays the tax.

(1) is the robust fix and matches the in-file precedent.

## Workaround for consumers today

Reconstructable from the same payload without a second call:

```js
const rem = (j.items.todos.find(i => i._remainder_count) || {})._remainder_count || 0;
const trueTodos = j.counts.todos + rem;   // 5 + 28 = 33 ✓
```

Verified against `list-todos` (33) and a raw file count (33).

**But the two are not the same predicate.** `scanTodos` counts *open* todos after
acknowledgement filtering; `list-todos` counts every `.md` in `todos/pending/`. They
agreed on both fixtures checked, but a consumer wanting "what is in pending" should call
`list-todos` rather than trust the arithmetic.

## Related, not the same

`_remainder_count` and `scan_error` sentinel rows are shaped like real items with empty
string fields, so a naive renderer produces blank rows. `scan_error` can appear in **any**
category (`:1265` and siblings), `_remainder_count` only in todos. Any consumer must
filter both from every array. Worth stating in the contract alongside whichever fix lands.
