---
id: SEED-001
status: triggered
planted: 2026-08-20
planted_during: no active milestone — gsd-core fork, personal branches
trigger_when: fired 2026-08-20 — operator promoted it; tracked as a todo
scope: small
build_with: skill-creator (Anthropic skill)
area: tooling
title: A `handoff` skill that merges rather than regenerates
problem_statement: .planning/research/2026-08-20-pause-work-missing-directives-and-template-defects.md
promoted_to: .planning/todos/pending/2026-08-20-build-a-handoff-skill-that-merges-rather-than-regenerates.md
---

## Why This Matters

*Derived from the spec and its problem statement, not from a separate interview.*

**The load-bearing difference is regenerate vs merge.** `/gsd-pause-work` rewrites the
handoff from current artifacts. The operator's standard is to read the prior handoff first
and carry forward every open item. Regeneration drops unresolved items **silently** — the
output looks complete while an open item has vanished. The spec is explicit that this
"cannot be expressed as a section addition", which is why it is a separate skill and not a
patch.

**The template captures state well and deltas to prior belief not at all.** State is
derivable from git and STATE.md by any agent at any time. What is *not* derivable is what
the session learned that contradicts, reorders, or re-scopes something already written
down — contradictions, reversals, and negative directives (the road not taken, the most
perishable class, which nobody writes down).

**Losing a correction produces a wrong action, not a redundant one.** Every other omission
costs a rediscovery cycle. This one costs correctness: a resuming agent trusts the artifact
on disk — normally the right instinct — and acts on a superseded instruction. Demonstrated
live in the 2026-08-20 session, where stale `CLAUDE.md` guidance sent an agent to build a
GSD workspace that the fork's branch model had already made unnecessary.

**Unverified state gets asserted as fact.** Nothing in the current workflow forces
measure-over-remember. Observed: a session authored a handoff while 18 commits behind
`origin/main`, asserting a `main` SHA that was not `main`, with no symptom until a peer
warned it.

## When to Surface

Trigger fired **2026-08-20** — promoted directly by the operator rather than waiting on
§7's four questions, which are decisions to be made while building rather than before.
Tracked as an actionable todo; see `promoted_to`.

## Scope Estimate

**Small** — a few hours. Inferred, not stated: the operator specified the *method*
(Anthropic's `skill-creator` skill) rather than a size. `skill-creator` handles SKILL.md
structure, description tuning, and evals, so the authoring half is largely mechanical and
the spec below is already implementation-ready. The residual work is the §7 decisions and
the merge/verify logic, not the scaffolding. Revise upward if the `/gsd-resume-work` read
side turns out to need changing too — a handoff nothing reads back is write-only.


> **Imported 2026-08-20.** Drafted in a separate `bootstrap-terraform` session. This is the
> proposed *solution* to the problem statement in
> `.planning/research/2026-08-20-pause-work-missing-directives-and-template-defects.md`;
> read that first. Filed as a seed, not a todo, because §7 holds four unanswered operator
> questions that block execution.
>
> **⚠ Correction to §1 — the durability argument, restated for this fork.**
> §1 says a `gsd-core/` patch is wiped by every GSD update while a skill under
> `~/.claude/skills/` survives, and concludes "prefer the skill". The conclusion holds, but
> the mechanism is different here and the `gsd-` prefix is **fine**.
>
> This fork is the install source: `bin/install.js` reads from `path.join(__dirname, '..')`
> (`:10000`) and writes to the target, so the recursive `rmSync` over `skills/gsd-*`
> (`:10823-10826`) is wipe-then-replace-*from this repo*. A `gsd-handoff` skill committed to
> `skills/` on a `local/*` branch is therefore durable, and keeps the namespace every other
> GSD skill uses.
>
> What actually destroys it is the **install command**: `/gsd-update` shells out to
> `npx -y --package=@opengsd/gsd-core@TAG` (`gsd-core/workflows/update.md:383-393`), which
> installs upstream's tree — and upstream has no `gsd-handoff`. Install with
> `node bin/install.js --claude --global` from this checkout instead.
>
> Also: §1's "Detail:" pointer to `~/.claude/notes/gsd-pause-work-defects.md` is stale;
> that document is now the `problem_statement` path in the frontmatter above.

---

# `/gsd-handoff` — reference spec

**Drafted 2026-08-20** from a `bootstrap-terraform` session that hand-authored both handoff files
twice, then diffed what it did against what `/gsd-pause-work` instructs.

**Purpose:** produce `.planning/HANDOFF.json` + `.planning/.continue-here.md` to a standard that
`/gsd-pause-work` does not enforce, such that `/gsd-resume-work` recovers not just *state* but
*unresolved obligations* — including ones that contradict what is committed on disk.

---

## 1. Why a new skill rather than a patch to `/gsd-pause-work`

`~/.claude/gsd-core/workflows/pause-work.md` (v1.10.0, 250 lines) is not wrong — it is **scoped to a
different case**. Its JSON schema (`:76-108`) is *task-shaped*: `plan`, `task`, `total_tasks`,
`completed_tasks[{id,name,commit}]`, `async_jobs`, `uncommitted_files`. It models **one phase paused
mid-execution**.

The operator's real case is **milestone-scoped across multiple repos and workstreams**. Six gaps,
all observed empirically:

| # | Gap |
|---|---|
| 1 | **No verify-after-write.** `<success_criteria>` (`:243`) contains zero verify/sweep/stale checks. |
| 2 | **No measure-don't-remember.** `## Context Detection` (`:12`) does file-*existence* checks only. |
| 3 | **No "contradicts an artifact on disk" slot.** `decisions[]` is `{decision, rationale, phase}`. |
| 4 | **No cross-session obligations ledger** — incl. which authorizations may not be relayed. |
| 5 | **Task-shaped schema** vs milestone-shaped reality. |
| 6 | **Duplicate `Critical Anti-Patterns` section** at `:139` (table) and `:184` (bullets). Template bug. |

Also: `/gsd-pause-work` implies **regeneration**. The operator's standard is a **merge**. That is the
load-bearing difference and it cannot be expressed as a section addition.

Detail: `~/.claude/notes/gsd-pause-work-defects.md`.

⚠️ Anything implemented inside `gsd-core/` is wiped by every GSD update. A standalone skill under
`~/.claude/skills/` survives. **Prefer the skill.**

---

## 2. Invocation

```
/gsd-handoff              # review since last handoff, merge, write both files
/gsd-handoff --full       # review the entire session, not just since last handoff
/gsd-handoff --dry-run    # print the merge plan + drop list; write nothing
```

No argument = the common case.

---

## 3. Process

### Step 1 — MEASURE (never remember)

Run these and populate from the output, not from session memory:

```bash
git fetch --prune --quiet origin
git log --oneline -1                       # current HEAD
git log --oneline -1 origin/main           # is local behind?
git rev-list --count HEAD..origin/main     # MUST be 0 before asserting repo state
git status --porcelain
glab mr list --output json | jq -r '.[] | "!\(.iid) \(.title)"'
ls .planning/phases/*/ | tail
grep -m1 '^status:' .planning/STATE.md
```

⛔ **If `rev-list --count` ≠ 0, pull before writing anything.** A handoff authored on a stale
checkout asserts a `main` SHA that is not `main`. (Observed: a session sat 18 commits behind without
noticing, and only a peer's warning surfaced it.)

### Step 2 — REVIEW (the part that is not derivable)

Scope: **since the last handoff commit** (`--full` overrides). Hunt for:

- **Unactioned items** — raised in-session, never closed
- **Things needing the operator** — attention, response, or a decision only they can make
- **Contradictions** — anything learned that overturns a committed artifact
- **Reversals** — a conclusion that replaced an earlier one, and which one is on disk
- **Negative directives** — what was decided *against*, and why (most perishable; nobody writes down the road not taken)
- **Ordering constraints** — X must precede Y, and the consequence of violating it
- **Cross-session obligations** — what peers owe you, what you owe them, non-relayable authorizations

⛔ **This is not a state dump.** A state dump is derivable from git + STATE.md by any agent at any
time. If every line of your output could have been produced without reading the session, the review
did not happen.

### Step 3 — MERGE (⭐ the load-bearing step)

Read the existing `HANDOFF.json` + `.continue-here.md` **first**. Carry forward every open item
unless it was genuinely resolved.

```bash
PRIOR=$(git log -1 --format=%H -- .planning/HANDOFF.json)
comm -23 \
  <(git show "$PRIOR":.planning/HANDOFF.json | jq -r '(.operator_decisions_pending[].id, .ready_not_started[].id)' | sort) \
  <(jq -r '(.operator_decisions_pending[].id, .ready_not_started[].id)' .planning/HANDOFF.json | sort)
```

**Every id in that output must have a stated reason for being dropped.** Non-empty output with no
stated reason = FAIL, do not commit.

Silent loss is the failure mode: a file that looks complete while an open item vanished.

### Step 4 — WRITE both files

Schemas in §4. Plain UTF-8, no `\uXXXX` escapes.

### Step 5 — VERIFY (the pass `/gsd-pause-work` lacks)

```bash
jq -e . .planning/HANDOFF.json >/dev/null            # parses
grep -c '\\\\u' .planning/HANDOFF.json               # 0 — no double-encoded escapes
```

Then the **stale-claim sweep** — grep BOTH files for every claim this session invalidated and
**read each hit**:

- the previous `main` SHA
- ids of blockers that are now resolved
- the previous `next_action`
- any "waiting on X" where X has happened

⭐ **Read, do not count.** A surviving hit may be a correct historical reference *or* a live stale
instruction, and only reading distinguishes them.

> Observed: a sweep found `next_action.operator_parallel` still instructing the reader to perform a
> sync that had already completed — *after* `status`, the repos block, the attention table, and an
> entire new results section had all been correctly updated. Handoffs fail this way because they are
> written in passes.

---

## 4. Schemas

### 4a. `HANDOFF.json` — DURABLE keys (the contract)

```json
{
  "version": "1.0",
  "timestamp": "<ISO8601>",
  "milestone": "v1.11",
  "phase": "76",
  "phase_name": "...",
  "next_phase": "99",
  "next_phase_name": "...",
  "status": "<one paragraph: where things stand and what is blocked on whom>",

  "repos": { "<repo>": "<state, incl. what is merged-but-unsynced>" },

  "next_action": {
    "primary": "<the single next command + why>",
    "then": "<what follows>",
    "read_first": ["<path> — <why it matters>"]
  },

  "operator_decisions_pending": [
    {"id": "SCREAMING-KEBAB", "blocking": true, "detail": "<what + the trap if any>"}
  ],

  "ready_not_started": [
    {"id": "...", "cmd": "/gsd-quick", "blocked_by": "<or omit>", "detail": "..."}
  ],

  "corrections_to_artifacts": [
    {"artifact": "<path>", "says": "...", "actually": "...", "evidence": "<file:line or command>"}
  ],

  "cross_session": {
    "<peer>": {"owes_us": "...", "we_owe": "...", "authorization_rule": "<e.g. takes authz DIRECTLY, never relayed>"}
  },

  "traps": ["<thing that costs a cycle if rediscovered>"]
}
```

### 4b. EPISODIC keys — allowed, but must be pruned

Milestone-specific keys (`sc6_result`, `the_big_change`, `shipped_this_session`,
`findings_worth_more_than_the_work`, `locked_decisions`) are fine **while their milestone is open**.
⛔ **Drop them at milestone close** rather than accreting forever.

The skill should warn when an episodic key references a closed milestone.

### 4c. `.continue-here.md`

YAML frontmatter (`context`, `milestone`, `phase`, `next_phase`, `status`, `last_updated`) then, in
order:

1. **One-line state** — `main` SHA, MRs merged, tree, open MRs
2. ⛔ **Corrections to artifacts on disk** — FIRST, before anything else. A reader who stops here must not act on a superseded instruction.
3. **⭐ Next action**, with a table showing which steps are already done
4. **Decided — do NOT re-litigate**
5. **Needs your attention** — table, one row per operator item
6. **Ready, not started**
7. **Cross-session**
8. **Traps**
9. **Read first**

---

## 5. Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| Regenerating from artifacts | Drops unresolved items silently. It is a **merge**. |
| State dump instead of review | Everything in it was already derivable; the session's real output is lost. |
| Asserting SHAs/MR state from memory | Observed 18-commit drift with no symptom. |
| Counting grep hits instead of reading them | Cannot distinguish a historical reference from a live stale instruction. |
| Burying a correction mid-file | A reader who stops early acts on the superseded version. |
| Flattening provenance to a verdict | "MET" vs "MET, corroborated by two independent methods" — the reader cannot judge whether to re-verify. |
| Accreting episodic keys forever | Next milestone inherits dead weight nobody dares delete. |

---

## 6. Success criteria

- [ ] `rev-list --count HEAD..origin/main` = 0 **before** any state was asserted
- [ ] Review scoped since last handoff (or `--full`), covering unactioned + operator-needed items
- [ ] Merge performed; **every dropped id has a stated reason**
- [ ] Both files written, plain UTF-8, JSON parses
- [ ] Stale-claim sweep run and each hit **read**
- [ ] Corrections-to-artifacts section present, or explicitly "none this session"
- [ ] Episodic keys reviewed against milestone status

---

## 7. Open questions for the operator

1. **Commit/MR behaviour** — operator is ambivalent. Default to committing + MR without gating on a nod? (Consistent with `feedback_dont_gate_docs_only_merges_on_operator`.)
2. **Where does `.continue-here.md` live** for milestone-scoped work? `/gsd-pause-work` writes it under the phase dir for phase context; this repo uses `.planning/.continue-here.md`. Confirm the milestone-scoped path is always repo-root.
3. **Should the skill refuse** when the review finds nothing, or write anyway?
4. **Multi-repo:** should peer-repo state be measured (`glab api` against their project) or accepted as reported by the peer session?
