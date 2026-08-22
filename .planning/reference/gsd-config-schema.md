# GSD `.planning/config.json` — merged key reference

> **Generated:** 2026-08-21T23:20:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** gsd-core/bin/shared/config-schema.manifest.json, gsd-core/bin/lib/capability-registry.cjs

> **Generated file — do not hand-edit.** Regenerate with
> `node scripts/gen-gsd-config-schema.cjs`, then diff.

Built against **GSD 1.11.0** (this repo's `next` @ `7cf6a079`, dev-source form /gsd:xxx not install-rewritten /gsd-xxx — no VERSION file ships in gsd-core/ source, commit ref is authoritative), from:

| Source | Contributes |
|---|---|
| `gsd-core/bin/shared/config-schema.manifest.json` | which key paths are valid (static + dynamic patterns) |
| `gsd-core/bin/shared/config-defaults.manifest.json` | default values |
| `gsd-core/bin/lib/capability-registry.cjs` → `configSchema` | owner, type, default, description for capability-owned keys |
| `gsd-core/references/planning-config.md` | prose descriptions for a subset of central keys |
| `gsd-core/bin/lib/config.cjs`, `bin/lib/secrets.cjs` | type/enum constraints and secret masking (transcribed into this generator) |

## Scope and caveats

- **Not exhaustive by construction.** `config-schema.cjs` resolves the capability schema *per project cwd*, composing any installed overlay capabilities. This dump covers **first-party capabilities only** — a project with third-party capabilities installed accepts keys not listed here.
- **Dynamic patterns admit unbounded keys.** The pattern table below is part of the valid key space; the static table cannot enumerate it.
- **"Appears in prose" ≠ documented.** The coverage check tests for the key in backtick form anywhere under `references/`, `workflows/`, `templates/`, `contexts/`. A key inside a `config-set` example counts as a hit.
- **No CLI dumps this.** `gsd-tools` exposes `config-get`, `config-set`, `config-path`, `config-ensure-section`, `migrate-config` — there is no schema-listing subcommand.

## Coverage

| Metric | Count |
|---|---|
| Static central key paths | 107 |
| Dynamic key patterns | 15 |
| Capability-owned keys (first-party) | 62 |
| **Total documented key paths** | **169** |
| Central keys with no description in any source | 54 |
| Central keys absent from all prose | 31 |
| Defaults present in neither registry | 1 |

Description provenance:

| Source | Keys |
|---|---|
| registry | 62 |
| (none) | 54 |
| planning-config.md | 52 |
| alias → sub_repos | 1 |

## Key reference

`R` = registry (`c` central, `cap` capability + owner). 🔒 = value masked by `config-get`/`config-set`.

### Top-level

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `brave_search` 🔒 | c | boolean: `true`, `false` | `false` | Enable Brave web search for research agent (requires `BRAVE_API_KEY`) |
| `claude_md_path` | c | string | `"./.claude/CLAUDE.md"` | _(undocumented)_ |
| `commit_docs` | c | boolean: `true`, `false` | `true` | Commit .planning/ artifacts to git (auto-false if .planning/ is gitignored) |
| `context` | c | enum: `dev` \| `research` \| `review` | `null` | Execution context profile that adjusts agent behavior: `"dev"` for development tasks, `"research"` for investigation/exploration, `"review"` for code review workflows |
| `context_window` | c | integer — positive integer (token count) | `200000` | Context window size; set `1000000` for 1M-context models |
| `exa_search` 🔒 | c | boolean: `true`, `false` | `false` | Enable Exa semantic search (requires `EXA_API_KEY`) |
| `firecrawl` 🔒 | c | boolean: `true`, `false` | `false` | Enable Firecrawl page scraping (requires `FIRECRAWL_API_KEY`) |
| `granularity` | c | string: `"coarse"`, `"standard"`, `"fine"` | (none) | Planning depth for phase plans (migrated from deprecated `depth`) |
| `jina` | c | — | — | _(undocumented)_ |
| `mode` | c | string: `"interactive"`, `"yolo"` | `"interactive"` | Operation mode: `"interactive"` shows gates and confirmations; `"yolo"` runs autonomously without prompts |
| `model_profile` | c | string: `"quality"`, `"balanced"`, `"budget"`, `"adaptive"`, `"inherit"` | `"balanced"` | Model selection preset for subagents |
| `parallelization` | c | boolean \| object: `true`, `false`, `{ "enabled": true }` | `true` | Enable parallel wave execution; object form allows additional sub-keys |
| `perplexity` | c | — | — | _(undocumented)_ |
| `phase_id_convention` | c | — | `null` | _(undocumented)_ |
| `phase_naming` | c | string: `"sequential"`, `"custom"` | `"sequential"` | Phase numbering: auto-increment or arbitrary string IDs |
| `project_code` | c | string — never number-coerced — leading zeros preserved | `null` | Prefix for phase dirs (e.g., `"CK"` produces `CK-01-foundation`) |
| `ref_search` | c | — | — | _(undocumented)_ |
| `resolve_model_ids` | c | boolean \| string: `false`, `true`, `"omit"` | `false` | Map model aliases to full Claude IDs; `"omit"` returns empty string |
| `response_language` | c | string \| null: Any language name | `null` | Language for user-facing prompts (e.g., `"Portuguese"`, `"Japanese"`) |
| `runtime` | c | — | — | _(undocumented)_ |
| `search_gitignored` | c | boolean: `true`, `false` | `false` | Include gitignored paths in broad rg searches via `--no-ignore` |
| `tavily_search` | c | — | — | _(undocumented)_ |

### workflow.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `workflow.agent_hint_routing` | c | boolean | `true` | _(undocumented)_ |
| `workflow.ai_integration_phase` | cap:ai-integration | boolean | `true` | Prompt for an AI-SPEC design contract before planning phases that involve AI systems. |
| `workflow.api_coverage_gate` | cap:ai-integration | boolean | `true` | Require an explicit API-coverage decision (full-by-default, opt-out-not-opt-in) before a phase that integrates an external API/SDK/service can seal. At plan:pre the planner is prompted to enumerate the API surface into COVERAGE.md; at verify:pre a blocking gate fails the seal unless the matrix exists with every non-integrated capability an explicit, reasoned opt-out. Independent of ai_integration_phase (applies to any external-API integration, not only AI). |
| `workflow.assumption_delta` | cap:assumption-delta | boolean | `true` | Enable the assumption-delta architecture checkpoint during planning. When a pluralization/optional/chosen signal is detected in the phase scope, the planner is prompted to re-ask whether the primary key / identity model still names the right thing. Advisory (non-blocking). |
| `workflow.auto_advance` | c | boolean: `true`, `false` | `false` | Auto-advance to next phase after completion |
| `workflow.auto_prune_state` | c | boolean: `true`, `false` | `false` | Automatically prune old STATE.md entries on phase completion (keeps 3 most recent phases) |
| `workflow.build_command` | c | string \| null: Any shell command | `null` | Build gate command run by the post-merge gate. Unset → build step auto-detected/skipped. |
| `workflow.code_review` | cap:code-review | boolean | `true` | Enable code-review participation in post-execution review flows. |
| `workflow.code_review_command` | c | string \| null: Any shell command | `null` | External code-review command integrated into `/gsd:ship`. The diff is piped to the command via stdin; the command must output JSON with a `verdict` field (`"APPROVED"` or `"REVISE"`). Non-zero exit or `"REVISE"` verdict blocks the ship workflow. When unset, the built-in review flow runs. Example: `my-review-tool --review`. |
| `workflow.code_review_depth` | cap:code-review | enum: `quick` \| `standard` \| `deep` | `"standard"` | Default depth for code review when no --depth override is supplied. |
| `workflow.context_coverage_gate` | c | boolean | `true` | _(undocumented)_ |
| `workflow.context_guard_mode` | c | enum: `auto` \| `warn` \| `off` | `"warn"` | Context exhaustion guard mode for `execute-phase`. Before each wave, the orchestrator self-assesses context pressure using degradation signals from `context-budget.md`. `"warn"` (default): emit a warning and recommend `/gsd:pause-work` when POOR tier is detected. `"auto"`: automatically invoke `/gsd:pause-work` before the next wave when POOR tier is detected. `"off"`: disable the guard. The guard is heuristic — no programmatic context-% API exists. |
| `workflow.cross_ai_command` | c | — | — | _(undocumented)_ |
| `workflow.cross_ai_execution` | c | — | — | _(undocumented)_ |
| `workflow.cross_ai_timeout` | c | — | — | _(undocumented)_ |
| `workflow.discuss_mode` | c | string: `"discuss"`, `"assumptions"` | `"discuss"` | Default mode for discuss-phase: `"discuss"` runs interactive questioning; `"assumptions"` analyzes codebase and surfaces assumptions instead |
| `workflow.drift_action` | cap:drift | enum: `warn` \| `auto-remap` | `"warn"` | Action taken by the codebase drift gate when the threshold is exceeded: warn (advisory message) or auto-remap (spawn gsd-codebase-mapper agent to refresh STRUCTURE.md). |
| `workflow.drift_threshold` | cap:drift | integer — positive integer | `3` | Minimum number of new structural elements (directories, barrel exports, migrations, routes) before the codebase drift gate triggers a warn or auto-remap action. |
| `workflow.human_verify_mode` | c | enum: `mid-flight` \| `end-of-phase` | `"end-of-phase"` | _(undocumented)_ |
| `workflow.inline_plan_threshold` | c | number: `0`–`10` | `2` | Plans with ≤N tasks execute inline instead of spawning a subagent |
| `workflow.max_discuss_passes` | c | number | `3` | _(undocumented)_ |
| `workflow.mvp_mode` | c | boolean: `true`, `false` | `false` | Persist the MVP-mode flag in config so every phase defaults to MVP framing without requiring `--mvp` on the CLI. Resolved via the chain: `--mvp` CLI flag → ROADMAP.md `**Mode:** mvp` field → this config value → `false`. When `true`, the planner, executor, verifier, and discovery surfaces (progress, stats, graphify) all treat the phase as an MVP vertical slice (UI → API → DB) of one user-visible capability. |
| `workflow.node_repair` | c | boolean: `true`, `false` | `true` | Attempt automatic repair of failed plan nodes |
| `workflow.node_repair_budget` | c | number: Any positive integer | `2` | Max repair retries per failed node |
| `workflow.nyquist_validation` | cap:nyquist | boolean | `true` | Enable Nyquist validation coverage auditing. |
| `workflow.pattern_mapper` | cap:pattern-mapper | boolean | `true` | Run the pattern mapper before planning when context or research is available. |
| `workflow.plan_bounce` | c | boolean | `false` | _(undocumented)_ |
| `workflow.plan_bounce_passes` | c | number | `2` | _(undocumented)_ |
| `workflow.plan_bounce_script` | c | — | `null` | _(undocumented)_ |
| `workflow.plan_check` | c | boolean: `true`, `false` | `true` | Run plan-checker agent to validate plans. _Alias:_ `plan_checker` is the flat-key form used in `CONFIG_DEFAULTS`; `workflow.plan_check` is the canonical namespaced form. |
| `workflow.plan_chunked` | c | boolean: `true`, `false` | `false` | Enable chunked planning mode. When `true`, the plan-phase orchestrator splits the single long-lived planner Task into a short outline Task followed by N short per-plan Tasks (~3–5 min each). Each plan is committed individually for crash resilience. Particularly useful on Windows where long-lived Tasks may hang on stdio. Also activated by the `--chunked` flag. |
| `workflow.plan_drift_precheck` | cap:drift | boolean | `true` | Enable the non-blocking codebase drift pre-check at plan:pre, before /gsd:plan-phase spawns the planner. When enabled, a stale STRUCTURE.md (structural additions exceeding drift_threshold) is surfaced up front as a warn-only advisory pointing to /gsd:map-codebase; it never blocks planning and never spawns the mapper agent. Separate from schema_drift_gate so autonomous/CI runs can silence the plan-time advisory while keeping the execute:wave:post gates enabled. |
| `workflow.plan_review_convergence` | c | — | — | _(undocumented)_ |
| `workflow.post_planning_gaps` | cap:gap-analysis | boolean | `true` | Run the post-planning gap analysis report after plans are generated. |
| `workflow.research` | cap:research | boolean | `true` | Run phase research before planning when research artifacts are missing or explicitly refreshed. |
| `workflow.research_before_questions` | c | boolean: `true`, `false` | `false` | Run research before interactive questions in discuss phase |
| `workflow.schema_drift_gate` | cap:drift | boolean | `true` | Enable the drift gates at execute:wave:post. When enabled, the schema drift gate blocks verification if schema-relevant files changed during execution but no database push command was executed; the codebase drift gate (non-blocking) warns when structural additions exceed the drift_threshold. |
| `workflow.schema_push_detection` | cap:schema-gate | boolean | `true` | Enable ORM schema push detection during planning. When schema-relevant files are detected in the phase scope, a [BLOCKING] push task is injected into the plan. |
| `workflow.security_asvs_level` | cap:security | integer — one of 1, 2, 3 (OWASP ASVS level) | `1` | OWASP ASVS level used by security review guidance. |
| `workflow.security_block_on` | cap:security | enum: `critical` \| `high` \| `medium` \| `low` \| `none` | `"high"` | Minimum open threat severity that blocks advancement. |
| `workflow.security_enforcement` | cap:security | boolean | `true` | Enable security threat-mitigation verification before phase advancement. |
| `workflow.skip_discuss` | c | boolean: `true`, `false` | `false` | Skip discuss phase entirely |
| `workflow.smart_zone_tokens` | c | integer — positive safe integer (token count) | `100000` | Smart-zone token budget for phase-effort estimation (#2630, ADR-2629). A phase whose estimate exceeds this is flagged with a split recommendation — advisory only, never a block. A *policy default*, not a benchmark constant: degradation begins before the advertised context window is full, but the effective ceiling is model- and task-dependent, so the calibration loop corrects it per project. _Alias:_ `smart_zone_tokens` is the flat-key form used in `CONFIG_DEFAULTS`; `workflow.smart_zone_tokens` is the canonical namespaced form. |
| `workflow.specless_probe_fallback` | c | boolean: `true`, `false` | `true` | Gate the SPEC-less probe fallback in `plan-phase`. When `true` (default), a phase that did not supply a `## Edge Coverage` / `## Prohibitions` SPEC section (header absent or present-but-empty) runs the existing probe protocol — the deterministic `edge-probe.cjs` for edges and an in-planner LLM recall pass for prohibitions — and authors the resulting predicates into PLAN.md `must_haves` (section-level precedence: a SPEC-supplied section is never re-run or overwritten). When `false`, the fallback is skipped but the skip is recorded: plan-phase emits a visible "probe fallback disabled" marker, never a silent skip. |
| `workflow.subagent_timeout` | c | number: Any positive integer (ms) | `300000` | Timeout for parallel subagent tasks (default: 5 minutes) |
| `workflow.tdd_mode` | cap:tdd | boolean | `false` | Enable TDD mode: planner annotates eligible tasks type:tdd and executor enforces RED/GREEN/REFACTOR gate sequence. |
| `workflow.test_command` | c | string \| null: Any shell command | `null` | Regression/test gate command run by execute-phase, audit-fix, and post-merge-gate. Unset → GSD auto-detects (Makefile / package.json / Cargo.toml / go.mod / pyproject.toml). |
| `workflow.test_gate_timeout` | c | — | — | _(undocumented)_ |
| `workflow.text_mode` | c | boolean: `true`, `false` | `false` | Use plain-text numbered lists instead of AskUserQuestion menus |
| `workflow.ui_phase` | cap:ui | boolean | `true` | Enable the UI design-contract gate during planning. |
| `workflow.ui_review` | cap:ui | boolean | `true` | Enable the retrospective UI audit. |
| `workflow.ui_safety_gate` | cap:ui | boolean | `true` | Block execution on unmet UI-SPEC contracts. |
| `workflow.use_worktrees` | c | boolean: `true`, `false` | `true` | Run executor agents in isolated git worktrees |
| `workflow.verifier` | c | boolean: `true`, `false` | `true` | Run verifier agent after execution |
| `workflow.windows_enforce` | cap:broken-windows | boolean | `false` | Enable the blocking ship:pre gate for the broken-windows ledger. When true (opt-in), /gsd-ship blocks while .planning/WINDOWS.md has any open entry. When false (default), windows are still tracked (the executor and verifier still populate WINDOWS.md via gsd-tools windows append) but ship does not block — teams can adopt tracking before enforcement. Issue #1950. |
| `workflow.worktree_skip_hooks` | c | — | — | _(undocumented)_ |

### planning.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `planning.commit_docs` | c | boolean: `true`, `false` | `true` | Alias for top-level `commit_docs` |
| `planning.search_gitignored` | c | boolean: `true`, `false` | `false` | Alias for top-level `search_gitignored` |
| `planning.sub_repos` | c | array: Array of relative path strings | `[]` | Child directories with independent `.git` repos (auto-detected) _(alias of `sub_repos`)_ |

### git.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `git.base_branch` | c | string \| null: Any branch name | `null` | Target branch for PRs and merges; auto-detects from `origin/HEAD` when `null` |
| `git.branching_strategy` | c | string: `"none"`, `"phase"`, `"milestone"` | `"none"` | Git branching approach for phase/milestone isolation |
| `git.create_tag` | c | boolean | `true` | Create git tags on milestone completion |
| `git.milestone_branch_template` | c | string: Template with `{milestone}`, `{slug}` | `"gsd/{milestone}-{slug}"` | Branch naming template for `milestone` strategy |
| `git.phase_branch_template` | c | string: Template with `{phase}`, `{slug}` | `"gsd/phase-{phase}-{slug}"` | Branch naming template for `phase` strategy |
| `git.quick_branch_template` | c | string \| null: Template with `{slug}` | `null` | Optional branch template for quick-task runs |

### model_policy.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `model_policy.budget` | c | — | — | _(undocumented)_ |
| `model_policy.high` | c | — | — | _(undocumented)_ |
| `model_policy.low` | c | — | — | _(undocumented)_ |
| `model_policy.medium` | c | — | — | _(undocumented)_ |
| `model_policy.provider` | c | — | — | _(undocumented)_ |

### effort.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `effort.default` | c | string | `"high"` | _(undocumented)_ |

### fast_mode.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `fast_mode.enabled` | c | boolean | `false` | _(undocumented)_ |

### review.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `review.default_reviewers` | c | array — normalized via normalizeConfiguredDefaultReviewers() | — | _(undocumented)_ |
| `review.llama_cpp_host` | cap:llama-cpp | string | `""` | Base URL of the llama.cpp OpenAI-compatible server. |
| `review.lm_studio_host` | cap:lm-studio | string | `""` | Base URL of the LM Studio OpenAI-compatible server. |
| `review.max_prompt_tokens` | c | — | — | _(undocumented)_ |
| `review.max_prompt_tokens_per_reviewer` | c | — | — | _(undocumented)_ |
| `review.max_prompt_tokens_per_reviewer.llama_cpp` | cap:llama-cpp | number | `-1` | Prompt-token budget for the llama.cpp reviewer lane. Unset is -1, a sentinel: 0 is a legitimate value meaning "do not trim this lane", so it cannot double as "not configured". |
| `review.max_prompt_tokens_per_reviewer.lm_studio` | cap:lm-studio | number | `-1` | Prompt-token budget for the LM Studio reviewer lane. Unset is -1, a sentinel: 0 is a legitimate value meaning "do not trim this lane", so it cannot double as "not configured". |
| `review.max_prompt_tokens_per_reviewer.ollama` | cap:ollama | number | `-1` | Prompt-token budget for the Ollama reviewer lane. Unset is -1, a sentinel: 0 is a legitimate value meaning "do not trim this lane", so it cannot double as "not configured". |
| `review.models.agy` | cap:antigravity | string | `""` | Model passed to the Antigravity reviewer lane. The key suffix is the lane binary/flag alias `agy`, not the slug `antigravity` — preserved verbatim so existing .planning/config.json files keep working. |
| `review.models.claude` | cap:claude | string | `""` | Model passed to the Claude reviewer lane. |
| `review.models.codex` | cap:codex | string | `""` | Model passed to the Codex reviewer lane. |
| `review.models.gemini` | cap:gemini | string | `""` | Model passed to the Gemini reviewer lane. |
| `review.models.kimi-code` | cap:kimi-code | string | `""` | Model passed to the Kimi Code reviewer lane. |
| `review.models.llama_cpp` | cap:llama-cpp | string | `""` | Model requested from the llama.cpp reviewer lane; empty discovers the first model from /v1/models. |
| `review.models.lm_studio` | cap:lm-studio | string | `""` | Model requested from the LM Studio reviewer lane; empty discovers the first model from /v1/models. |
| `review.models.ollama` | cap:ollama | string | `""` | Model requested from the Ollama reviewer lane; empty discovers the first model from /v1/models. |
| `review.models.opencode` | cap:opencode | string | `""` | Model passed to the OpenCode reviewer lane. |
| `review.ollama_host` | cap:ollama | string | `""` | Base URL of the Ollama OpenAI-compatible server. |

### plan_review.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `plan_review.source_grounding` | c | boolean | `true` | _(undocumented)_ |
| `plan_review.source_grounding_authority` | c | enum: `grep` \| `intel` \| `treesitter` \| `lsp` \| `scip` | `"grep"` | _(undocumented)_ |

### code_quality.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `code_quality.fallow.enabled` | c | — | — | _(undocumented)_ |
| `code_quality.fallow.mcp` | c | — | — | _(undocumented)_ |
| `code_quality.fallow.profile` | c | enum: `minimal` \| `standard` \| `strict` | — | _(undocumented)_ |
| `code_quality.fallow.scope` | c | enum: `phase` \| `repo` | — | _(undocumented)_ |

### security.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `security.injection_blocking` | c | boolean | `false` | _(undocumented)_ |

### agent_skills_security.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `agent_skills_security.trusted_global_roots` | c | — | — | _(undocumented)_ |

### capabilities.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `capabilities.auto_update` | c | boolean | `false` | _(undocumented)_ |
| `capabilities.strict_known_registries` | c | — | `null` | _(undocumented)_ |

### statusline.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `statusline.context_position` | c | enum: `front` \| `end` | — | _(undocumented)_ |
| `statusline.show_context_tokens` | c | boolean | — | _(undocumented)_ |
| `statusline.show_git` | c | boolean | — | _(undocumented)_ |
| `statusline.show_last_command` | c | — | — | _(undocumented)_ |
| `statusline.state_format` | c | enum: `full` \| `compact` | — | _(undocumented)_ |

### hooks.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `hooks.context_warnings` | c | boolean: `true`, `false` | `true` | Show warnings when context budget is exceeded |
| `hooks.workflow_guard` | c | boolean | `false` | _(undocumented)_ |

### manager.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `manager.flags.discuss` | c | string: Any CLI flags string | `""` | Flags passed to `/gsd:discuss-phase` from manager (e.g., `"--auto --analyze"`) |
| `manager.flags.execute` | c | string: Any CLI flags string | `""` | Flags passed to execute workflow from manager |
| `manager.flags.plan` | c | string: Any CLI flags string | `""` | Flags passed to plan workflow from manager |

### executor.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `executor.stall_detect_interval_minutes` | c | — | — | _(undocumented)_ |
| `executor.stall_threshold_minutes` | c | — | — | _(undocumented)_ |

### planner.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `planner.stall_detect_interval_minutes` | c | — | — | _(undocumented)_ |
| `planner.stall_threshold_minutes` | c | — | — | _(undocumented)_ |

### graphify.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `graphify.auto_update` | c | boolean | `false` | _(undocumented)_ |
| `graphify.build_timeout` | c | — | — | _(undocumented)_ |
| `graphify.enabled` | cap:graphify | boolean | `false` | Enable the graphify knowledge-graph command + skill. |
| `graphify.graph_path` | c | — | — | _(undocumented)_ |

### claude_md_assembly.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `claude_md_assembly.mode` | c | — | — | _(undocumented)_ |

### ship.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `ship.pr_body_sections` | c | array — validated by validateShipPrBodySections() | `[]` | Append-only project-specific PR body sections. Each entry has `heading`, optional `enabled`, and one or more of `source`, `template`, or `fallback`. Disabled entries remain in onboarding config but do not render. Core sections remain required and cannot be removed or replaced. |

### features.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `features.global_learnings` | c | boolean: `true`, `false` | `false` | Enable injection of global learnings from `~/.gsd/knowledge/` into agent prompts |
| `features.thinking_partner` | c | boolean: `true`, `false` | `false` | Enable conditional extended thinking at workflow decision points (used by discuss-phase and plan-phase for architectural tradeoff analysis) |

### learnings.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `learnings.max_inject` | c | number: Any positive integer | `10` | Maximum number of global learning entries to inject into agent prompts per session |

### claude_orchestration.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `claude_orchestration.enabled` | cap:claude-orchestration | boolean | `false` | Master toggle for the Claude orchestration capability. Default-off + BETA: the Workflow-tool execution backend and the ultraplan plan-offload surface are inert unless this is true. When false, loop behaviour is byte-identical to a non-Claude runtime (inline/manual dispatch). |
| `claude_orchestration.execution_backend` | cap:claude-orchestration | enum: `auto` \| `workflow` \| `inline` | `"auto"` | Which execute-phase dispatch backend to use when the capability is enabled. 'auto' (default) activates the Workflow backend only when the runtime is Claude AND the Workflow tool is detected AND the Agent SDK meets claude_orchestration.min_agent_sdk_version; otherwise it falls back to inline. 'workflow' forces the Workflow backend when the tool is present AND the Agent SDK meets the floor (still fails closed to inline if the tool is absent or the SDK is too old — the floor applies in both modes). 'inline' forces today's manual one-agent-per-message dispatch regardless of tool availability. |
| `claude_orchestration.min_agent_sdk_version` | cap:claude-orchestration | string | `"0.3.149"` | Minimum Agent SDK version required to activate the Workflow backend under execution_backend='auto'. Defaults to 0.3.149 (the release that introduced the Workflow tool). Raise to pin a higher floor; the detection seam fails closed to inline for any runtime reporting an older or unknown version. |

### external_job.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `external_job.artifact_dir` | cap:external-job | string | `"Artifacts/jobs"` | Root for per-job artifact directories (e.g. Artifacts/jobs/<jobid>/). Avoids fixed log paths and hardcoding a cluster/project layout. Surfaced by the adapter (`slurm-adapter.cjs submit` prints the resolved value); override via GSD_EXTERNAL_JOB_ARTIFACT_DIR. |
| `external_job.backend` | cap:external-job | enum: `slurm` | `"slurm"` | Scheduler backend. SLURM is the first adapter; the field is the pluggability seam for future backends (LSF, PBS, Kubernetes batch). Core never interprets this value. |
| `external_job.enabled` | cap:external-job | boolean | `false` | Master toggle for the async external-job producer capability. Default-off: the core loop consumes manifests whether or not this is on, but no manifest is ever written unless an executor opts in here. |
| `external_job.poll_timeout_ms` | cap:external-job | number | `15000` | Hard timeout (ms) for the scheduler poll subprocess (squeue, with sacct fallback). Read by the adapter (env GSD_SLURM_POLL_TIMEOUT_MS overrides). |
| `external_job.submit_timeout_ms` | cap:external-job | number | `30000` | Hard timeout (ms) for the scheduler submit subprocess (e.g. sbatch). Bounded per CLAUDE.md unbounded-subprocess policy. Read by the adapter (env GSD_SLURM_SUBMIT_TIMEOUT_MS overrides). |

### intel.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `intel.enabled` | cap:intel | boolean | `false` | Enable the intel code-intelligence command. |

### mempalace.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `mempalace.auto_capture_hooks` | cap:mempalace | boolean | `false` | Reserved / not yet implemented: will install MemPalace's native stop/precompact Claude Code hooks for passive mid-session capture (the capability's hooks array is currently empty). |
| `mempalace.capture_artifacts` | cap:mempalace | boolean | `true` | File CONTEXT/PLAN/SUMMARY and learnings into the palace at phase boundaries. |
| `mempalace.cross_project_tunnels` | cap:mempalace | boolean | `false` | Propose/create cross-wing tunnels at ship:post. |
| `mempalace.diary_journal` | cap:mempalace | boolean | `true` | Write a per-agent diary entry at ship:post. |
| `mempalace.enabled` | cap:mempalace | boolean | `false` | Master toggle for the MemPalace memory capability. |
| `mempalace.memory_mode` | cap:mempalace | enum: `augment` \| `kg_backend` \| `replace` | `"augment"` | How MemPalace relates to GSD native memory during recall/capture. 'augment' (default): the palace is an additive layer alongside .planning/graphs/ — native memory stays authoritative. 'kg_backend': knowledge-graph queries resolve against the palace's temporal KG as the primary source, with .planning/graphs/ as fallback. 'replace': recall resolves through the palace as the source of truth, native memory as fallback. Every mode stays onError:skip and default-resilient — an unreachable palace degrades to native memory, and GSD keeps writing .planning/graphs/ so no memory is lost. Cross-mode migration of existing .planning/graphs/ into the palace is a separate, not-yet-implemented concern. |
| `mempalace.mirror_kg` | cap:mempalace | boolean | `true` | Mirror decisions/learnings into MemPalace's temporal knowledge graph. |
| `mempalace.recall_on_discuss` | cap:mempalace | boolean | `true` | Inject wake-up + search recall at discuss:pre. |
| `mempalace.recall_on_plan` | cap:mempalace | boolean | `true` | Produce MEMORY-RECALL.md at plan:pre. |
| `mempalace.wing` | cap:mempalace | string | `""` | Palace wing name; empty derives from project_code / project dir. |

### profile-pipeline.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `profile-pipeline.enabled` | cap:profile-pipeline | boolean | `false` | Enable the developer profiling pipeline commands (scan-sessions, extract-messages, profile-sample, write-profile, etc.). |

### refactor.*

| Key | R | Type / values | Default | Description |
|---|---|---|---|---|
| `refactor.complexity_jump_delta` | cap:refactor-trigger | number | `5` | Complexity growth above which a refactor proposal is surfaced even when the absolute threshold is not reached. Measured against the function's anchor — the score recorded the last time the function was consciously dispositioned — so it accumulates across phases and catches slow creep the absolute threshold would miss. Strictly greater, as with the threshold. |
| `refactor.complexity_threshold` | cap:refactor-trigger | number | `15` | Absolute per-function complexity above which a refactor proposal is surfaced. Semantics match ESLint's `complexity: {max: N}` — the trigger is STRICTLY GREATER, so a score of exactly N does not trigger. Default 15 follows SonarSource's default; ESLint's own default is 20 and radon's rank C begins at 11. Raise it if proposals feel like noise. |
| `refactor.trigger_enabled` | cap:refactor-trigger | boolean | `false` | Enable the complexity-triggered refactor hook. When true, an execute:post step evaluates the complexity of the files the phase touched and writes a scoped refactor proposal if a function crosses refactor.complexity_threshold or jumps past refactor.complexity_jump_delta. Opt-in; when false the hook never runs. Issue #1953. |
| `refactor.trigger_strict` | cap:refactor-trigger | boolean | `false` | Record an untriaged refactor proposal as an open `deviation` entry in the broken-windows ledger, so it becomes a tracked task that must be resolved before ship. Off by default and deliberately so: a blocking complexity number is a metric an executor can satisfy by splitting one coherent function into two incoherent ones, so the entry clears on the proposal being DISPOSITIONED (gsd-tools refactor accept\|decline), never on the score improving. Ship blocking is the broken-windows capability's existing ship:pre gate — enable it with workflow.windows_enforce. With broken-windows absent, strict mode still records the proposal locally and says so; it cannot block on its own. Advisory mode (the default) surfaces the same proposal and tracks nothing. |

## Dynamic key patterns

These accept any key matching the regex. They are valid config keys but cannot be enumerated.

| Shape | Regex | Top-level |
|---|---|---|
| `agent_skills.<agent-type>` | `^agent_skills\.[a-zA-Z0-9_-]+$` | `agent_skills` |
| `features.<feature_name>` | `^features\.[a-zA-Z0-9_]+$` | `features` |
| `claude_md_assembly.blocks.<section>` | `^claude_md_assembly\.blocks\.[a-zA-Z0-9_]+$` | `claude_md_assembly` |
| `model_profile_overrides.<runtime>.<opus\|sonnet\|haiku>` | `^model_profile_overrides\.[a-zA-Z0-9_-]+\.(opus\|sonnet\|haiku)$` | `model_profile_overrides` |
| `models.<planning\|discuss\|research\|execution\|verification\|completion>` | `^models\.(planning\|discuss\|research\|execution\|verification\|completion)$` | `models` |
| `granularities.<planning\|discuss\|research\|execution\|verification\|completion>` | `^granularities\.(planning\|discuss\|research\|execution\|verification\|completion)$` | `granularities` |
| `dynamic_routing.<enabled\|escalate_on_failure\|max_escalations\|provider_escalation\|tier_models.<light\|standard\|heavy>>` | `^dynamic_routing\.(enabled\|escalate_on_failure\|max_escalations\|provider_escalation\|tier_models\.(light\|standard\|heavy))$` | `dynamic_routing` |
| `model_overrides.<agent-id>` | `^model_overrides\.[a-zA-Z0-9_-]+$` | `model_overrides` |
| `effort.routing_tier_defaults.<light\|standard\|heavy>` | `^effort\.routing_tier_defaults\.(light\|standard\|heavy)$` | `effort` |
| `effort.agent_overrides.<agent-id>` | `^effort\.agent_overrides\.[a-zA-Z0-9_-]+$` | `effort` |
| `fast_mode.routing_tier_defaults.<light\|standard\|heavy>` | `^fast_mode\.routing_tier_defaults\.(light\|standard\|heavy)$` | `fast_mode` |
| `fast_mode.agent_overrides.<agent-id>` | `^fast_mode\.agent_overrides\.[a-zA-Z0-9_-]+$` | `fast_mode` |
| `review.reviewer_instances.<instance-name>.<cli\|model\|agent> (#1517)` | `^review\.reviewer_instances\.[a-zA-Z0-9_-]+\.(cli\|model\|agent)$` | `review` |
| `model_policy.runtime_tiers.<runtime>.<opus\|sonnet\|haiku> (#3587)` | `^model_policy\.runtime_tiers\.[a-zA-Z0-9_-]+\.(opus\|sonnet\|haiku)$` | `model_policy` |
| `phase_commit_docs.<phase-id> — per-phase commit_docs override (#3587). The <phase-id> segment is a hand-copy of the canonical PHASE_NUMBER_TOKEN_SOURCE grammar owned by src/phase-id.cts (#2128); this manifest is hand-maintained JSON so it cannot import that constant. Pinned against drift by the behavioral parity test in tests/commit-docs-bypass.test.cjs (folded 'phase-commit-docs' block, describe block 'E', #3587) — do not hand-edit this pattern without updating that test.` | `^phase_commit_docs\.\d+[A-Z]?(?:\.\d+)*$` | `phase_commit_docs` |

## Runtime state keys

Accepted by the validator but written by GSD itself — not user-facing settings.

- `workflow._auto_chain_active`

## Gaps

### Central keys with no description anywhere (54)

Valid and settable, but neither registry nor `planning-config.md` explains them. Where this generator has a verified type/enum constraint from `config.cjs`, it is shown in the table above.

- `agent_skills_security.trusted_global_roots`
- `capabilities.auto_update`
- `capabilities.strict_known_registries`
- `claude_md_assembly.mode`
- `claude_md_path` (mentioned in prose, not defined)
- `code_quality.fallow.enabled`
- `code_quality.fallow.mcp`
- `code_quality.fallow.profile` — constraint at `config.cjs:780`
- `code_quality.fallow.scope` — constraint at `config.cjs:777`
- `effort.default`
- `executor.stall_detect_interval_minutes`
- `executor.stall_threshold_minutes`
- `fast_mode.enabled`
- `graphify.auto_update` (mentioned in prose, not defined)
- `graphify.build_timeout` (mentioned in prose, not defined)
- `graphify.graph_path`
- `hooks.workflow_guard`
- `jina`
- `model_policy.budget` (mentioned in prose, not defined)
- `model_policy.high` (mentioned in prose, not defined)
- `model_policy.low` (mentioned in prose, not defined)
- `model_policy.medium` (mentioned in prose, not defined)
- `model_policy.provider` (mentioned in prose, not defined)
- `perplexity`
- `phase_id_convention`
- `plan_review.source_grounding` (mentioned in prose, not defined) — constraint at `config.cjs:785`
- `plan_review.source_grounding_authority` (mentioned in prose, not defined) — constraint at `config.cjs:790`
- `planner.stall_detect_interval_minutes`
- `planner.stall_threshold_minutes` (mentioned in prose, not defined)
- `ref_search`
- `review.default_reviewers` (mentioned in prose, not defined) — constraint at `config.cjs:824`
- `review.max_prompt_tokens`
- `review.max_prompt_tokens_per_reviewer`
- `runtime` (mentioned in prose, not defined)
- `security.injection_blocking`
- `statusline.context_position` — constraint at `config.cjs:757`
- `statusline.show_context_tokens` — constraint at `config.cjs:761`
- `statusline.show_git` — constraint at `config.cjs:771`
- `statusline.show_last_command`
- `statusline.state_format` — constraint at `config.cjs:767`
- `tavily_search`
- `workflow.agent_hint_routing`
- `workflow.context_coverage_gate` (mentioned in prose, not defined)
- `workflow.cross_ai_command` (mentioned in prose, not defined)
- `workflow.cross_ai_execution` (mentioned in prose, not defined)
- `workflow.cross_ai_timeout` (mentioned in prose, not defined)
- `workflow.human_verify_mode` (mentioned in prose, not defined) — constraint at `config.cjs:749`
- `workflow.max_discuss_passes` (mentioned in prose, not defined)
- `workflow.plan_bounce` (mentioned in prose, not defined)
- `workflow.plan_bounce_passes` (mentioned in prose, not defined)
- `workflow.plan_bounce_script` (mentioned in prose, not defined)
- `workflow.plan_review_convergence`
- `workflow.test_gate_timeout` (mentioned in prose, not defined)
- `workflow.worktree_skip_hooks`

### Central keys absent from all prose (31)

- `agent_skills_security.trusted_global_roots`
- `capabilities.auto_update`
- `capabilities.strict_known_registries`
- `claude_md_assembly.mode`
- `code_quality.fallow.enabled`
- `code_quality.fallow.mcp`
- `code_quality.fallow.profile`
- `code_quality.fallow.scope`
- `effort.default`
- `executor.stall_detect_interval_minutes`
- `executor.stall_threshold_minutes`
- `fast_mode.enabled`
- `graphify.graph_path`
- `hooks.workflow_guard`
- `jina`
- `perplexity`
- `phase_id_convention`
- `planner.stall_detect_interval_minutes`
- `ref_search`
- `review.max_prompt_tokens`
- `review.max_prompt_tokens_per_reviewer`
- `security.injection_blocking`
- `statusline.context_position`
- `statusline.show_context_tokens`
- `statusline.show_git`
- `statusline.show_last_command`
- `statusline.state_format`
- `tavily_search`
- `workflow.agent_hint_routing`
- `workflow.plan_review_convergence`
- `workflow.worktree_skip_hooks`

### Defaults present in neither registry (1)

Keys with a shipped default that the validator would reject on `config-set`. Verify whether anything reads them before relying on either behavior.

- `planning.granularity` — default `"standard"`
