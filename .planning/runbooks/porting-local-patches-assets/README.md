# Assets — evidence and RED-test templates for the porting runbook

Companion to `../porting-local-patches-to-the-fork.md`. These are the **executable**
artifacts behind that runbook's claims, rescued from `/tmp` (ephemeral) on 2026-08-20.

Produced by nine validation agents, one per concern. The runbook carries the distilled
findings; these are the scripts that produced them. Reruns need the same environment the
runbook's §1 describes (`/tmp/gsd-norm`, `/tmp/gsd-pristine-1100` — recreate per §1 if gone).

| File | Concern | What it is |
|---|---|---|
| `4.1-plan-scan-RED.test.cjs` | 4.1 | **Ready-to-use RED test.** Mirrors `row11` in `tests/plan-count-single-owner.test.cjs:173-184`. Fails on current 1.11.0 source (`2 !== 1`), passes with the patch. Drop in as a new table row. |
| `graphify/4.3b-seedfloor-counterexample.cjs` | 4.3b | **The invariant-break proof, and the RED-test template.** 3-node fixture where seed `n0` survives at budget 120 and is **evicted at budget 150** — larger budget, smaller result. Deliberately multi-seed with differentiated match quality, which is exactly what the existing suite's fixture cannot generate. |
| `graphify/4.3b-fastcheck-blindspot.cjs` | 4.3b | **Proves the CI blind spot.** Runs `arbGraph` (`tests/graphify-query.test.cjs:513-538`) under the repo's pinned fast-check config (`numRuns: 200, seed: 42`) and counts runs producing ≥2 seeds. Result: **0 / 200**. This is why `:560`/`:587` pass while the contract they protect is broken. |
| `graphify/4.3-pristine-vs-patched.cjs` | 4.3 / 4.3b | Before/after on the real corpus at `--budget 2000`: pristine 727 nodes / 0 edges / miss vs patched 11 / 9 / met. Also demonstrates byte-identical output above the budget cliff. |
| `glab/fence-derive.sh`, `glab/fence-create-pr.sh`, `glab/stubbin/` | 4.9 | **The inertness proof.** Verbatim fence contents extracted from patched `ship.md`, plus `gh`/`glab` stubs (`glab auth status` → 0, `gh auth status` → 1). Run each script as a *separate* shell to reproduce: `$FORGE` is empty at guard time and `create_pr` dispatches to `gh` on a GitLab-only remote. No network, creates nothing. |

## What is NOT here

The nine agents' full prose reports exist only in the originating session transcript. The
runbook holds the distillation — verdicts, corrected claims, and the file:line citations —
but not every command and its raw output. If a specific finding needs re-deriving, the
scripts above cover the load-bearing ones; the rest are cheap to re-run from the runbook's
own citations.

## Caveat on reruns

`4.3-pristine-vs-patched.cjs` reads a **live** project graph
(`~/Documents/git/bootstrap-terraform/.planning/graphs/graph.json`), not a frozen fixture.
Exact digits drift day to day — 727 seeds today vs the patch comment's 701, ~51× vs its 47×.
The phenomenon and its magnitude re-derive; the precise numbers do not.
