> **Filed 2026-08-20.** Problem statement. The proposed solution is
> `.planning/seeds/SEED-001-handoff-skill.md`, which supersedes the "Proposed directive"
> lines below for defects 1-5: it argues the fix is a **separate skill**, not a patch to
> `pause-work.md`, because the regenerate-vs-merge difference cannot be expressed as a
> section addition. Defect 6 and the phase-glob bug are genuine `pause-work.md` bugs and
> are NOT addressed by that skill.
>
> Citations re-verified against v1.11.0 at filing: `pause-work.md` is byte-stable across
> 1.10.0 -> 1.11.0 (250 lines both; `Context Detection`:12, `write_structured`:66,
> `success_criteria`:243 all unmoved), and the duplicate `Critical Anti-Patterns` at :139
> and :184 is still present. Every line number below holds.
>
> Its own "Status" section references `~/.claude/notes/gsd-glab-port.md`; that is now
> `.planning/research/2026-08-17-glab-forge-port-map.md`.

---

# `/gsd-pause-work` — missing directives and template defects

**Verified 2026-08-20 against installed gsd-core `1.10.0`**, file
`~/.claude/gsd-core/workflows/pause-work.md` (250 lines). Every line number below was grepped
fresh; re-grep the quoted anchor rather than trusting the number after any gsd-core update.

**Source of the finding:** a long `bootstrap-terraform` session that hand-authored
`.planning/HANDOFF.json` + `.planning/.continue-here.md` **twice**, then diffed what it had actually
done against what the workflow instructs. Every gap below is something that session performed and
the workflow does not require — not a speculative improvement.

---

## First, what is NOT missing

Worth recording because it was asserted and was wrong on inspection:

- **`HANDOFF.json` IS specified.** `pause-work.md:76-108` carries a full JSON template, **18 fields**,
  including `async_jobs`, `human_actions_pending` (with `blocking`), typed `blockers`
  (`technical|human_action|external`), `decisions`, `uncommitted_files`, `context_notes`. The claim
  that it is "named only in the commit line" is false — it appears 4 times and has its own
  `<step name="write_structured">`.
- **`<decisions_made>`** already captures rationale ("chose X over Y because…").
- **The Critical Anti-Patterns table** (`:139`) already models negative directives well — it carries
  `severity: blocking|advisory` plus a *prevention mechanism* column, and discuss-phase/execute-phase
  parse it to enforce an understanding check on `blocking` rows. That is better than most handoff
  formats.

The gaps below are what remains after crediting all of that.

---

## Defect 1 — no verify-after-write pass ⭐ highest value

`<success_criteria>` (`:243`) contains **zero** occurrences of verify / sweep / stale / re-read /
check-output. Nothing requires reading the produced files back.

**Why it matters, empirically:** the source session ran a stale-claim sweep after each regeneration
and it caught a real defect **both times**. The second pass found `next_action.operator_parallel`
still instructing the reader to perform a sync that had already completed — *after* `status`, the
repos block, the attention table, and an entire new results section had all been correctly updated.

**Handoffs fail exactly this way** because they are written in passes: you update the section you are
thinking about, and the stale instruction hiding in a sibling field survives.

**Proposed directive:** after writing, grep both files for every claim the session invalidated (old
`main` SHA, completed blockers, superseded next-actions, resolved questions) and **read each hit**.
Counting is not enough — a surviving hit may be a correct historical reference or a live stale
instruction, and only reading distinguishes them.

## Defect 2 — nothing requires state be measured rather than remembered

`## Context Detection` (`:12`) does file-**existence** checks (active phase / spike / sketch /
deliberation). Nothing instructs re-deriving the facts about to be asserted.

The source session opened each regeneration with `git log`, `glab mr list`, `ls` on the phase dir,
and `grep` on STATE.md before writing a word; its commit messages say *"against measured state, not
remembered state."* That discipline was the operator's, not the workflow's.

**Proposed directive:** a `measure` step before `write_structured` — re-read HEAD, open MRs, phase
dir contents and STATE.md status, and populate from those, not from session memory.

## Defect 3 — no slot for "this contradicts an artifact on disk"

`decisions[]` is `{decision, rationale, phase}`. There is no shape for a conclusion that **overturns
a committed file**.

**Concrete instance:** an audit committed to `main` recommended manufacturing drift to prove a
scheduled check fires. A later review established the ordering was backwards — the check's only "red
tick" was probably a cancelled CI job, so the rehearsal had to be preceded by an `interruptible` fix
or it would prove nothing. A handoff recording only *"decided to fix interruptible first"* loses that
**the file on disk says the opposite**, and a resuming agent trusts the artifact — which is normally
correct — and gets it backwards.

This is the one class where losing the note produces a **wrong action** rather than a redundant one.

**Proposed section:**
```
## Corrections to Artifacts on Disk
| Artifact | What it says | What is actually true now | Evidence |
```

## Defect 4 — no cross-session obligations ledger

`blockers[]` holds *your* blockers. There is no shape for what a peer owes you, what you owe them,
and — load-bearing — **which authorizations may not be relayed**.

**Concrete instance:** *"`bca-ng` takes operator authorization DIRECTLY, never relayed — has
correctly refused four times."* That fact prevents real harm (the peer can trigger a cluster-wide
sync), and nothing in the schema holds it. The source session carried a bespoke `cross_session` key
in both regenerations for exactly this.

**Proposed field:** `cross_session: {peer: {owes_us, we_owe, authorization_rule}}`.

## Defect 5 — the schema is task-shaped, the state was milestone-shaped

`plan`, `task`, `total_tasks`, `completed_tasks[{id, name, commit}]` models **one phase paused
mid-execution**. Real state was milestone-level across three repos and two workstreams.

Every one of these was invented because nothing fit: `repos`, `the_big_change`, `sc6_result`,
`locked_decisions`, `findings_worth_more_than_the_work`, `shipped_this_session`, `traps`.

Not obviously a defect — a phase-scoped handoff is a reasonable design. But **the milestone-scoped
case is unserved**, and `/gsd-resume-work` reads whatever shape the last session invented, so two
sessions produce incompatible files.

## Defect 6 — duplicate `Critical Anti-Patterns` section (template bug)

Two sections with the same heading and **different shapes**:

- `:139` `## Critical Anti-Patterns` — a **table** (`Pattern | Description | Severity | Prevention Mechanism`)
- `:184` `## Critical Anti-Patterns (do NOT repeat these)` — a **bullet list** (`- [ANTI-PATTERN]: … → …`)

Nothing indicates which is authoritative. In practice one gets filled and the other is left as
placeholder text, and a reader cannot tell which. The `:139` table is the one that discuss-phase and
execute-phase parse, so the `:184` bullets are the redundant copy.

**Fix:** delete `:184`, or make it an explicit pointer to the table.

---

## The meta-directive underneath 1, 3 and 4

Add a pass before regeneration:

> **What did this session learn that CONTRADICTS, REORDERS, or RE-SCOPES something already written
> down? Write those first.**

The template captures **state** well and **deltas to prior belief** not at all. In a fast-moving
session the artifact and the truth diverge faster than either gets rewritten — three consecutive MRs
in the source session were each correct when written and superseded within hours, not through
carelessness but because evidence kept arriving after the document did.

---

## Status

**Not reported upstream.** Unknown whether open-gsd accepts workflow-level contributions; note that
`.planning/research/2026-08-17-glab-forge-port-map.md` records the maintainer closing a different request with *"we use
GitHub exclusively"*, so upstream receptiveness should not be assumed.

If implemented locally, this is a `gsd-core/` edit and therefore **wiped by every GSD update** —
register it in `~/.claude/runbooks/gsd-update-runbook.md` and append to
`~/.claude/scripts/gsd-local-patches-<version>.diff` per the standing rule in `~/.claude/CLAUDE.md`.
