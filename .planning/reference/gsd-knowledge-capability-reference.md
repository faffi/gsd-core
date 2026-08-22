# GSD Knowledge-Capability Reference — Steady State

> **Generated:** 2026-08-21T23:20:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** gsd-core/src/intel.cts, gsd-core/src/graphify.cts, gsd-core/bin/lib/capability-registry.cjs

**Scope:** project-agnostic. Applies to any GSD-managed repo.
**Derived from:** gsd-core `next` @ `2b9713a6` (v1.10.0). File:line refs are to the gsd-core source
repo unless prefixed `~/.claude/` (the installed copy).

> **2026-08-20 — header bumped to `next` @ `7cf6a079` (v1.11.0), claims NOT re-verified line-by-line.**
> Spot-check only, against this session's own v1.11.0 CHANGELOG.md read: zero entries touch
> intel/graphify/gsd-graph internals. One mempalace-adjacent fix landed (#3479/#3527, absent-key
> defaults for `mirror_kg`/`diary_journal` now resolve to their declared `true` default instead of
> requiring the key to be explicitly present) — does not contradict anything currently claimed here.
> Treat every file:line citation below as **unverified against 1.11.0** until a real pass is done;
> this bump only means "checked for a reason to distrust it wholesale, found none."
>
> **EXCEPTION — §6 (intel) and §4's `grep`→`intel` auto-upgrade were empirically re-verified
> 2026-08-20** against `next` @ `7cf6a079` (v1.11.0): capability gate, the 9-subcommand surface,
> `loop render-hooks plan:pre` activation, `drift-guard authority`, and the plan-phase §7.9 dispatch
> path were each executed or read directly. §6 carries one correction (the "never auto-runs" claim was
> wrong) — see the CORRECTED note there. Probes ran through the shipped `gsd-core/bin/lib`, which on
> that checkout is stale relative to `src/` (`runtime-homes.cjs` lacks
> `NON_REGISTRY_CONFIG_HOME_DESCRIPTORS`, breaking 8 CLI-shelling tests in `tests/intel.test.cjs`);
> `intel`'s own src↔shipped surface was diffed and is identical."
**Purpose:** define the STEADY STATE for the four knowledge capabilities — intel, mempalace,
graphify, gsd-graph — and the validation that proves a project is in it.

> **Standard of proof:** claims cite the code that *executes* them (`file:line`). Where a behavior is
> only described in docs or workflow prose with no enforcing code, it is marked as such — "documented"
> is not "verified." Where docs and code disagree, the code wins and §10b records the divergence.

---

## 0. The one thing to internalize

This codebase family has a recurring failure mode: **a feature is declared, schema-validated,
registry-materialized, rendered into a prompt — and never executed.** Every layer reports success.
There is no diagnostic anywhere.

It shows up in both directions:

| Direction | Example | Consequence |
|---|---|---|
| **Declared, never dispatched** | `refactor-trigger`'s `refactor evaluate` (execute:post) — one of only two `ref.command` steps, and the only undispatched one | the step silently never runs |
| **Dispatched, never declared** | graphify's planner/researcher steps | `loop render-hooks` reports nothing; no `when:` gate, no `onError`, no way to disable |
| **Believes it integrates** | gsd-graph writes `gsd_graph` into gsd-core's config | gsd-core has never heard of the key |

**Therefore: never trust a manifest. Trace to the dispatcher.** When validating any capability, the
question is not "is it declared?" but "what code path executes it, and is that path reachable?"

---

## 1. STEADY STATE — the target

A project is in steady state when all of the following hold. §2 is the validation script.

### 1a. Config keys

| Key | Steady-state value | Why |
|---|---|---|
| `context_window` | **`1000000`** (or your model's real window) | ABSENT ⇒ 200k default (`src/config.cts:88`) ⇒ **frontmatter-only reads**. ⚠️ Prose contract: read-depth lives in workflow-markdown conditionals the agent interprets, not in code. Nothing enforces compliance |
| `intel.enabled` | `true` | feeds the plan drift guard; also auto-upgrades its resolver (§4) |
| `mempalace.enabled` | `true` | 5 real lifecycle steps, the only fully-wired capability |
| `mempalace.wing` | explicit string | absent ⇒ derived from `project_code`/dirname ⇒ drifts |
| `mempalace.memory_mode` | `augment` | palace is additive; native memory stays authoritative |
| `graphify.enabled` | `true` | if you maintain a code graph |
| `graphify.auto_update` | **`false`** | cannot fire in branch-based workflows (§5) — leaving it on is theater |
| `graphify.graph_path` | **unset** | inert for both agent consumers (§5); use symlinks instead |
| `plan_review.source_grounding` | `true` (default) | enables the drift guard |
| `plan_review.source_grounding_authority` | **do not set** | `intel.enabled` auto-upgrades it (§4) |
| `workflow.discuss_mode` | `assumptions` (optional) | reads codebase first, asks only for corrections |
| `workflow.research_before_questions` | `true` (optional) | research informs the questions |

### 1b. Artifacts present and current

- `.planning/intel/` — 5 JSON files, `intel validate` passes
- `.planning/graphs/graph.json` — `graphify status` shows `commits_behind` small
- mempalace wing exists and is populated (`mempalace status`)
- `.gsd-graph/graph.v1.json` — only if you use gsd-graph

### 1c. Structural invariants

- **Config is COMMITTED.** `.planning/config.json` is git-tracked; worktrees inherit only merged state.
- **Every worktree can reach the graph** (symlink — §5).
- **No stale MCP registrations** pointing at absent stores.
- **Local patches to `~/.claude/gsd-core/` are backed up outside it** (§9).

---

## 2. VALIDATE — run this in any project

Read-only. Prints a PASS/FAIL per invariant.

```bash
#!/usr/bin/env bash
# gsd-capability-check — run from a GSD project root
G=~/.claude/gsd-core/bin/gsd-tools.cjs
ok(){ printf '  ✅ %s\n' "$1"; }; bad(){ printf '  ❌ %s\n' "$1"; }; warn(){ printf '  ⚠️  %s\n' "$1"; }

echo "── config ──"
node -e '
const c=require("./.planning/config.json");
const g=(k)=>k.split(".").reduce((a,p)=>a&&a[p],c);
const want={"context_window":v=>v>=500000,"intel.enabled":v=>v===true,
 "mempalace.enabled":v=>v===true,"graphify.enabled":v=>v===true};
for(const[k,f]of Object.entries(want)){const v=g(k);
 console.log((f(v)?"  ✅ ":"  ❌ ")+k+" = "+JSON.stringify(v===undefined?"(ABSENT)":v));}
const auth=g("plan_review.source_grounding_authority");
if(auth!==undefined)console.log("  ⚠️  plan_review.source_grounding_authority is set ("+auth+") — redundant, intel.enabled auto-upgrades it");
if(!g("mempalace.wing"))console.log("  ⚠️  mempalace.wing unset — derives from project_code/dirname (optional, but explicit is safer)");
if(g("graphify.graph_path")!==undefined)console.log("  ⚠️  graphify.graph_path is set — INERT for planner/researcher (§5)");
if(g("graphify.auto_update")===true)console.log("  ⚠️  graphify.auto_update true — verify gate 5 can pass (§5)");
'

echo "── config committed? ──"
git ls-files --error-unmatch .planning/config.json >/dev/null 2>&1 || bad "UNTRACKED — worktrees will never see it"
git diff --quiet HEAD -- .planning/config.json 2>/dev/null && \
  git ls-files --error-unmatch .planning/config.json >/dev/null 2>&1 && ok "committed" || \
  bad "uncommitted or untracked — worktrees will not see it"

echo "── intel ──"
[ -d .planning/intel ] && ok ".planning/intel/ exists" || bad ".planning/intel/ MISSING — spawn gsd-intel-updater (§3c); the CLI cannot populate it"
node "$G" intel validate --raw >/dev/null 2>&1 && ok "intel validate passes" || bad "intel validate FAILS — index empty or malformed"

echo "── graphify ──"
node "$G" graphify status --raw 2>/dev/null | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{const j=JSON.parse(d);
if(j.disabled)return console.log("  ❌ disabled: "+j.message);
if(j.exists===false)return console.log("  ❌ no graph: "+j.message);
console.log("  nodes="+j.node_count+" edges="+j.edge_count+" stale="+j.stale+" commits_behind="+j.commits_behind+" commit_stale="+j.commit_stale);
if(j.commit_stale===true)console.log("  ⚠️  commit_stale TRUE but NOTHING acts on it — agents branch only on `stale` (§5)");
}catch(e){console.log("  ❌ unparseable")}})'

echo "── mempalace ──"
command -v mempalace >/dev/null && ok "CLI present" || bad "CLI missing"
W=$(node -e 'try{console.log(require("./.planning/config.json").mempalace?.wing||"")}catch(e){}')
[ -n "$W" ] && { mempalace status 2>/dev/null | grep -q "WING: $W" && ok "wing '$W' populated" || bad "wing '$W' NOT in palace"; }

echo "── worktree graph reachability ──"
for w in $(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | tail -n +2); do
  [ -e "$w/.planning/graphs/graph.json" ] && ok "$(basename "$w")" || bad "$(basename "$w") — no graph (symlink it, §5)"
done

echo "── local patches backed up? ──"
[ -d ~/gsd-patch-backup ] && ok "~/gsd-patch-backup exists" || warn "no backup — see §9 before any /gsd-update"
```

---

## 3. ENABLE — bringing a project to steady state

### 3a. Config

```bash
gsd-tools query config-set context_window 1000000     # or your model's real window
gsd-tools query config-set intel.enabled true          # ALSO auto-upgrades the drift guard — §4
gsd-tools query config-set mempalace.enabled true
gsd-tools query config-set mempalace.wing <explicit-wing-name>
gsd-tools query config-set mempalace.memory_mode augment
gsd-tools query config-set graphify.enabled true
# optional planning-depth knobs
gsd-tools query config-set workflow.discuss_mode assumptions
gsd-tools query config-set workflow.research_before_questions true
```

**Do NOT set `plan_review.source_grounding_authority`** — see §4.

### 3b. Commit — LOAD-BEARING

`.planning/config.json` is **git-tracked**. Worktrees get a fresh checkout, so uncommitted config is
**invisible to every worktree** — and worktrees are where GSD runs parallel execution.

**A capability can be ON for the orchestrator and OFF for every executor simultaneously, with no
diagnostic anywhere.** `{"disabled": true}` reads identically to "user never enabled it."

If the repo is MR-gated (no direct-to-main — check `git.branching_strategy` and whether main's
history is merge-only), branch it:
```bash
git checkout -b chore/gsd-capability-surface
git add .planning/config.json && git commit -m "chore: enable capability surface"
git push -u origin HEAD   # then open the MR
```
⚠️ **Worktrees see the change when the MR MERGES, not when you commit.**

### 3c. Populate

```bash
# intel — the CLI CANNOT populate; spawn the agent
Agent(subagent_type="gsd-intel-updater", prompt="Refresh .planning/intel/ for this project")
gsd-tools query intel validate      # MANDATORY — an empty index fails silently
gsd-tools query intel api-surface   # optional here — plan-phase.md §7.9 also runs it every plan (§6)

gsd-graph enable                    # only if using gsd-graph
```

⚠️ **`gsd-tools intel update` does NOT populate.** `intelUpdate` (`src/intel.cts:307-314`) returns
`{action:'spawn_agent'}` and writes nothing — same pre-flight pattern as `graphify build` (§5). The
five JSON files are written only by the agent (`saveRefreshSnapshot`, `src/intel.cts:326`: "Called by
the intel-updater agent after completing a refresh").

⚠️ **`/gsd-map-codebase --query refresh` is not a reliable route.** `skills/gsd-map-codebase/SKILL.md:38`
routes `--query` to "the intel workflow" — **no such workflow exists** in source or the installed tree.
Plain `/gsd-map-codebase` is a different command entirely (writes `.planning/codebase/*.md`, never
touches intel). Precedent for silent failure here: CHANGELOG #1000/#1037 — agent wrote `files.json`,
library read `file-roles.json`, `intel query` returned nothing with no error. Hence the mandatory validate.

### 3d. Worktree graph symlinks

```bash
for w in $(git worktree list --porcelain | awk '/^worktree /{print $2}' | tail -n +2); do
  ln -sfn "$(git rev-parse --show-toplevel)/.planning/graphs" "$w/.planning/graphs"
done
```

### 3e. MCP budget

Every enabled MCP server injects its schema **every turn, whether called or not** (~5k tokens each).
`gsd-core/references/context-budget.md` calls this "the biggest cost lever you don't own." Savings
multiply across every subagent. Toggle in `.claude/settings.json` via `enabledMcpjsonServers` /
`disabledMcpjsonServers` — **not** `.planning/config.json`. Audit before long planning phases.

---

## 4. The drift guard — auto-upgrade (undocumented)

Two keys (`docs/CONFIGURATION.md:726-727`):

| Key | Default | Role |
|---|---|---|
| `plan_review.source_grounding` | `true` | **Enables** the guard: resolves every symbol a PLAN.md cites against the live tree |
| `plan_review.source_grounding_authority` | `"grep"` | **Picks the resolver.** `treesitter`/`lsp`/`scip` are reserved, no effect |

🔑 **`intel.enabled: true` SILENTLY AUTO-UPGRADES the authority `grep` → `intel`.**
`src/plan-drift-guard.cts:88-97`:
```ts
export function getEffectiveAuthority(authority, intelEnabled) {
  const validated = validateAuthority(authority);      // undefined → 'grep'
  if (validated === 'grep' && intelEnabled === true) return 'intel';
  return validated;
}
```
Undocumented in CONFIGURATION.md. **Never set the authority key** — it is redundant, and pinning it
to `grep` does NOT opt out (the rule fires on exactly that value).

**Blast radius: BOUNDED.** `AUTHORITY_RUNGS` (`:40-47`): `grep:0 intel:1 treesitter:2 lsp:3 scip:4`,
`HARD_BLOCK_RUNG_THRESHOLD = 3`. `intel` is rung 1 — a `MISSING` verdict is advisory
(`needs-acknowledgement`, `hardBlock:false`) under both grep and intel. **An empty index degrades
signal quality; it cannot block planning.** Run `intel validate` anyway — an empty index makes every
notice noise you learn to ignore.

---

## 5. graphify — what to expect

**Purpose:** parses **code** into `.planning/graphs/graph.json`; injects a slice into the planner and
researcher prompts before planning.

**Consumers (exhaustive):**

| Consumer | Budget (code-enforced) | Queries (prompt only) | Source |
|---|---|---|---|
| `gsd-planner` | 2000 tok | 1 | `gsd-core/references/planner-load-graph-context.md:8,15,23` |
| `gsd-phase-researcher` | 1500 tok | 2-3 | `agents/gsd-phase-researcher.md:570,576,584` |
| `/gsd-graphify` skill | unbounded | — | display only |

The token budget is real: `applyBudget` (`src/graphify.cts:382-481`) drops edges by confidence tier to
fit. The **query count is prose only** — nothing stops an agent calling `graphify query` more times.

Nothing else reads `graph.json`. gsd-core registers **no** graphify MCP server — any
`mcp__graphify__*` tools come from your own MCP config and **nothing in GSD's lifecycle uses them**.

**Build** — there is no working `build` verb. `gsd-tools graphify build` is pre-flight only
(`src/graphify.cts:715-746`; the `spawn_agent` name is vestigial per `SKILL.md:152`):
```bash
graphify update .          # GRAPHIFY_FORCE=1 if refused for having fewer nodes
cp graphify-out/graph.json .planning/graphs/graph.json
cp graphify-out/GRAPH_REPORT.md .planning/graphs/GRAPH_REPORT.md
gsd-tools graphify build snapshot
gsd-tools graphify status
```
`graph.html` is skipped above ~5000 nodes.

**`graphify.graph_path` is INERT for both agent consumers.** Both gate on a hardcoded
`ls .planning/graphs/graph.json` and skip before the CLI runs. The CLI honors the key; the agents
never reach it. **Leave unset; symlink instead (§3d).**

**`commit_stale`/`commits_behind` are DISPLAY-ONLY.** Emitted at `src/graphify.cts:650-651`; only
consumer is the skill's `Source commit:` line. Both agents branch **only on `stale`** (24h mtime). A
graph N commits behind with `stale:false` produces **no annotation** — agents plan against a
provably-stale graph.
⚠️ **Namesake trap:** identically-named fields exist for STATE.md freshness (#2573,
`src/state.cts:2424-2483` → `src/verify.cts:1612-1617`) and *those* ARE consumed. A bare grep
conflates them.

**`graphify.build_timeout` is never enforced.** Read at `src/graphify.cts:735`, emitted as
`timeout_seconds`, only occurrence anywhere. `docs/FEATURES.md:2670` REQ-GRAPH-03 is false as
implemented.

**Auto-update hook** (`hooks/gsd-graphify-update.sh`) gates, in order: (1) tool==Bash · (2) command
matches `git commit|merge|pull|rebase --continue|cherry-pick` or exactly `gsd-tools query commit` ·
(3) `$CI` empty · (4) in a git repo · (5) **`CURRENT_BRANCH == DEFAULT_BRANCH`** · (6) both
`graphify.enabled` AND `graphify.auto_update` true · (7) `graphify` on PATH · (8) no PID lock.

⚠️ **Gate 5 is structurally incompatible with branch-based workflows.** With
`git.branching_strategy: "phase"`, `src/commands.cts:1102-1125` checks out `feat/{phase}-{slug}`
before committing — every phase commit lands off-default and gate 5 rejects it. MR-based flows
advance local main by fetch, matching no gate-2 pattern. **Keep `auto_update: false` and rebuild
manually.**

**Silent failure modes:** graph absent → skip; capability disabled → `disabledResponse()`, no `stale`
key, reads as "no results"; **skill de-surfaced → everything disabled EVEN WITH
`graphify.enabled: true`** (`active = (installed && surfaced) && configActivation`,
`capability-state.cts:85-101`); `graph.json` unparseable → agents have no `error` branch.
`writeSnapshot` is the only verb with **no** capability guard.

**Version warning is a false negative** on `uv tool`/pipx installs — the identity probe uses PATH `python3`, which cannot see an isolated venv. Nothing gates on it. Install with `uv tool install graphifyy` (the in-code `uv pip install` hint at `src/graphify.cts:127` is wrong).

---

## 6. intel

**Purpose:** LLM-curated structured facts in `.planning/intel/` that agents query **instead of doing
expensive codebase exploration reads** (`agents/gsd-intel-updater.md:31`).

Five files (`src/intel.cts:29-35`): `stack.json`, `file-roles.json`, `api-map.json`,
`dependency-graph.json`, `arch-decisions.json`.

**CLI surface** (`src/intel-command-router.cts:109`): `api-surface`, `diff`, `extract-exports`,
`patch-meta`, `query`, `snapshot`, `status`, `update`, `validate`. ⚠️ **`update` does NOT populate** —
it returns a `spawn_agent` directive (§3c), whose message circularly tells you to run `intel update`.
Only the agent writes the files.

⚠️ **7 of the 9 subcommands honour `intel.enabled`; `extract-exports` and `patch-meta` do not.**
The gate lives inside each `intel.cts` function, not in the router, so those two run with intel
disabled — verified 2026-08-20: with `{"intel":{"enabled":false}}`, `status` returns the `disabled`
envelope while `patch-meta` still rewrote `_meta.updated_at` on a `path.resolve(cwd, …)` target.
Deliberate (`src/intel.cts:534`, `:575`: "Does not gate on isCapabilityActive … for use by agents
building intel data"), since the updater agent calls both while populating — but it does mean
`patch-meta` is an always-live `_meta.updated_at`/`version` patcher on any existing parseable JSON
path, regardless of the capability's activation state.

**Strongest consumer:** the plan drift guard (`gsd-core/workflows/plan-review-convergence.md:242`) —
catches plans citing functions that don't exist.

⚠️ **Its `plan:pre` step IS dispatched — but by a bespoke handler, not the generic contract.**
The *generic* dispatcher at `plan-phase.md:459`, labelled "**Generic** step hook dispatch
contract," has only `ref.skill` and `ref.agent` branches, so a `ref.command` step falls straight
through it (all five `execute:post` sites are narrower still — `autonomous.md:438`,
`code-review-fix.md:87`, `code-review.md:90`, `execute-phase.md:1233`, `quick.md:552` filter on
`kind=="step" && ref.skill=="code-review"`). **But `plan-phase.md:650-665` §7.9 "Regenerate
API-SURFACE.md (intel gate)" matches the hook by `capId == "intel"` and runs a hardcoded
`gsd_run intel api-surface` (`:660`), setting `API_SURFACE_PATH` (`:661`) which step 8 injects into
the planner prompt as a HINT (`:718`, `:728-730`).** §7.9 predates this correction (present at
`2b9713a6`/v1.10.0), so the earlier "never auto-runs" claim here was wrong at 1.10.0 too, not merely
stale. Both other planning hosts reach it transitively — `autonomous.md:365,380,392` and
`plan-review-convergence.md:154,438` both call `Skill(skill="gsd-plan-phase")` rather than
reimplementing `plan:pre`.

⚠️ **…but §7.9 is bypassable, and the bypass fires exactly where intel matters most.** `§7.8`
(pattern-mapper) has two jumps that land on **step 8**, skipping 7.9 entirely:
`plan-phase.md:613` ("If PATTERNS.md already exists … Skip to step 8") and `:607` ("or Step 8 if
pattern mapper is disabled"). `API_SURFACE_PATH` is assigned **only** at `:661`, and `:728` wraps the
whole `<intel_surface_hint>` block in `${API_SURFACE_PATH ? …}` — so on either bypass the hint is
silently absent from the planner prompt, with no warning. PATTERNS.md exists from cycle 1 of
`/gsd:plan-review-convergence`, so **every replan cycle after the first drops the API-surface hint** —
in the one workflow whose source-grounding pass (§4) is intel's strongest consumer. Verified by
inspection at `next`@`7cf6a079`, not by execution. Running `intel api-surface` manually before a
replan is still worthwhile for that reason.

> **CORRECTED 2026-08-20** (empirical trace, gsd-core `next` @ `7cf6a079`/v1.11.0). Prior text
> read "⚠️ Its `plan:pre` step is a `ref.command`, which NO shipped workflow dispatches … run it
> manually after each refresh." That generalised a true statement about the *generic* contract into a
> false one about intel. Verified: `loop render-hooks plan:pre --raw` lists the intel hook only when
> `intel.enabled` is true, and §7.9 dispatches it by capId. The residual true case is
> `refactor-trigger`'s `refactor evaluate` at execute:post — zero handlers, genuinely inert (though
> also opt-in: `refactor.trigger_enabled` defaults to `false`, so it is disabled-and-undispatched,
> not live-and-broken).

The *mechanism* warning still stands: nothing anywhere reads `ref.command` generically
(`gsd-core/references/loop-hook-dispatch.md:45-56` specifies it; no workflow implements it), so a
third-party capability declaring a `ref.command` step gets silence. intel escapes only because
plan-phase hardcodes its command. Upstream #3559 is the same class for `ship:pre` gates.

Written by an LLM agent ⇒ stale the moment code changes, and only as accurate as the agent. The guard
at `gsd-intel-updater.md:126` exists because it got this wrong: exports must be real identifiers,
"if an export string contains a space, it is wrong."

**Split:** intel answers *"what is this and what does it export?"*; graphify answers *"what else does
this touch?"*

---

## 7. mempalace — the reference implementation

**The only capability wired correctly end-to-end.** Use it as the model when judging the others.

Five declared steps, all **dispatched**: `discuss:post` (capture), `plan:pre` (recall →
MEMORY-RECALL.md), `plan:post` (capture), `verify:post` (capture), `ship:post`
(agent `gsd-mempalace-curator`). `ship.md:508-510` implements a **generic** dispatch contract naming
the curator explicitly.

Why it works where others don't: it **declares** its steps in the manifest (so `loop render-hooks`
reports them) and uses only `ref.skill`/`ref.agent` — the two kinds workflows actually dispatch.

**Config note:** `mempalace.*` keys are NOT in gsd-core's central schema manifest — they come from the
capability's own `config` block, which is why `query config-set mempalace.*` is accepted. Same pattern as
`graphify.enabled` (capability-owned) vs `graphify.auto_update`/`build_timeout`/`graph_path`
(central manifest). A `validKeys` grep returning nothing for mempalace is expected.

**`memory_mode: augment`** means the palace is **additive** — native `.planning/` memory stays
authoritative and both are written. The palace and `~/.claude/projects/*/memory/` are **parallel, not
synchronized**: fixing a native memory does not fix its palace counterpart.

**Watch:** a single `general` room accumulating tens of thousands of drawers degrades recall.
`mempalace split` exists for this. Compare wings that have `testing`/`src`/`general` splits.

---

## 8. gsd-graph — separate product, ZERO gsd-core integration

**Purpose:** builds a citation-grounded graph from **docs** (`.planning/`, `docs/`, README —
explicitly *not* full `src/`) into `.gsd-graph/graph.v1.json`. CLI + its own MCP server.

**gsd-core has ZERO awareness.** 0 hits for `.gsd-graph`, `gsd_graph`, `graph.v1.json`,
`@opengsd/gsd-graph`. No `capabilities/gsd-graph/`. Touches no loop point, appears in no agent prompt
— **nothing in a GSD workflow will ever invoke it.** It is a peer of gsd-core, not a component.

⚠️ **GREP TRAP:** naive `grep -i 'gsd-graph'` returns ~229 hits in gsd-core, **ALL `gsd-graphify`
substring collisions.** A `(?!ify)` negative lookahead is mandatory.

**The `gsd_graph` key coexists safely.** `gsd-graph enable` writes it into `.planning/config.json`
(`<pkg>/dist/pipeline/enable.js:120-141`). gsd-core rejects it as a *set* target
(`query config-set gsd_graph.enabled true` → exit 1) but **tolerates it in the file**:
```
gsd-tools: warning: unknown config key(s) in .planning/config.json: gsd_graph — these will be ignored
```
…and still exits 0. **Expect that warning permanently; do not chase it.**

**MCP registrations survive a disable.** `gsd-graph mcp install` writes to three destinations —
`~/.claude.json`, `~/.codex/config.toml` (**GLOBAL**), and project `.mcp.json` — so removing one
catches none of the others. **Audit all three when disabling.** The first two embed machine-local
node paths and rot on a node-version change; project `.mcp.json` is deliberately portable
(`preferPortable: true`, `src/cli/mcp-install.ts:398-409`) so it can be committed. Against a missing
store the server still starts and serves its full tool list — no init-time error.

**Value:** `ask`/`why` with citations over `.planning/` history — "why did we decide X three
milestones back" — a question shape graphify's seed-and-expand BFS handles poorly. Run it
deliberately as a standalone CLI.

---

## 9. Local patches to `~/.claude/gsd-core/`

`/gsd-update` **overwrites** `gsd-core/`, `agents/gsd-*`, `skills/gsd-*`, `commands/gsd/`.

🛑 **`--reapply` is NOT a reliable safety net.** `gsd-local-patches/` is populated **during** an
update run (manifest hash comparison → back up → replace), not continuously. A patch made after the
last update is **not in the backup**. Verify before trusting it:
```bash
ls ~/.claude/gsd-local-patches/            # check contents AND mtime vs your patch
```

**Back up manually before any update:**
```bash
mkdir -p ~/gsd-patch-backup
cp ~/.claude/gsd-core/<patched-files> ~/gsd-patch-backup/
```

Note `gsd-core/bin/lib/*.cjs` are **generated build artifacts** (gitignored in the source repo);
source of truth is `src/*.cts`, which is **not shipped in the npm package**. Patching the `.cjs` is
the only option for an installed copy — but don't send that diff upstream, and expect it to vanish.

**Coherence risk:** a patch spanning a reference + a router + a lib works only while all three are
patched. A partial overwrite leaves a reference instructing an agent to pass a flag the router
rejects — a hard failure, not a silent one.

---

## 10. Quick reference

```bash
# freshness
gsd-tools graphify status
gsd-tools intel validate
mempalace status
gsd-graph status

# rebuild graphify (manual — auto-update usually cannot fire, §5)
graphify update . && cp graphify-out/graph.json .planning/graphs/graph.json && \
  gsd-tools graphify build snapshot

# intel refresh — UNVERIFIED path, always validate after (§3c)
/gsd-map-codebase --query refresh && gsd-tools intel validate && gsd-tools intel api-surface
#   plain /gsd-map-codebase does NOT populate intel — different artifact set

# what actually runs at a lifecycle point (the ONLY authoritative answer)
gsd-tools loop render-hooks plan:pre --raw

# NEVER
/gsd-update          # back up patches first, prefer --reapply, verify the backup (§9)
```

## 10b. Canonical docs — and where code contradicts them

**Canonical coverage is thin.** Only mempalace has a how-to
(`docs/how-to/enable-cross-session-memory-with-mempalace.md`). graphify and intel have none —
`docs/FEATURES.md` + `docs/CONFIGURATION.md` only. gsd-graph is absent from gsd-core docs entirely.
Hook-kind authority is `docs/how-to/develop-a-capability.md`.

**From the mempalace how-to — these change what you do:**
- `mempalace.enabled` is the **only required key** (line 31). `wing`/`memory_mode` are optional
  refinements; `augment` is already the default (line 41).
- Safe to leave `enabled: true` on machines without mempalace installed (line 134) — degrades to off.
- Per-point opt-outs exist: `recall_on_discuss`, `recall_on_plan`, `capture_artifacts` (lines 87-93).
  Use these instead of disabling the capability.
- `auto_capture_hooks` is forward-declared and **inert** (line 108) — installs nothing.

**Where the docs claim behavior the code does not implement — code wins:**

| Doc claim | Reality | Evidence |
|---|---|---|
| REQ-GRAPH-03: build runs within `graphify.build_timeout` | never enforced; read once, no consumer | `src/graphify.cts:735,741` |
| REQ-GRAPH-06: `graph_path` honored by `query/status/diff` | true for CLI, **inert for planner/researcher** | §5 |
| `capability.json`: graphify "build" subcommand | builds nothing — pre-flight only | `src/graphify.cts:715-746` |
| `SKILL.md:38`: "run the intel workflow" | **no intel workflow exists** | §3c |

⚠️ Do not generalize CLI surfaces between capabilities: graphify has no top-level `snapshot`
(it is `build snapshot`), but **intel does** (`src/intel-command-router.cts:109`).

**Canonical guidance corroborates §0:** `develop-a-capability.md:81` defines hook refs as `ref.skill`
and `ref.agent` only — **`ref.command` is never mentioned**, and :221-222 describe dispatch purely in
those terms. The two shipped `ref.command` steps are outside the documented contract.

---

## 11. Verifying a capability yourself

1. `capabilities/<id>/capability.json` — what does it declare (`steps`, `hooks`, `gates`, `contributions`)?
2. `gsd-tools loop render-hooks <point> --raw` — does it appear at runtime?
3. **Find the dispatcher.** Grep the host workflow for the `render-hooks <point>` call site and read
   how it filters. A workflow matching one `ref.skill` string will silently drop every other hook.
4. `ref.command` ⇒ **assume dead** unless you find the executing call site.
5. Absent from render-hooks but demonstrably running ⇒ it's wired via agent prose or the installer;
   it has no `when:` gate and cannot be disabled through config.
