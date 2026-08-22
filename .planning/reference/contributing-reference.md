# gsd-core contribution reference (local, untracked)

> **Generated:** 2026-08-21T23:20:00Z
> **GSD version:** 1.11.0-58-g026e2a73
> **Source:** CONTRIBUTING.md (this repo)

**Purpose.** A distilled, line-cited index of every rule in `CONTRIBUTING.md` that can close a PR,
fail CI, or waste work — plus the local-machine gotchas that CI cannot see.

**Provenance.** Derived from `CONTRIBUTING.md` @ blob `42f667d0`, 1155 lines, last touched by
`9faacc0c` (2026-08-07, `test(#3148)`). Branch `next` @ `343835fa`. All `:N` refs are line numbers
in that revision — re-verify if the blob hash changes.

**This file is untracked.** `.gitignore:12` ignores `.claude/`, so nothing here can enter a diff.
Caveat: `bin/install.js` syncs into `.claude/agents/`; it should not touch files at `.claude/` root,
but if this file ever disappears, that is the suspect.

---

## 0. Does CONTRIBUTING.md say to use GSD on gsd-core itself?

**No — and the omission looks deliberate.** Verified empirically:

| Probe | Result |
|---|---|
| `/gsd-*` slash commands aimed at contributors | **Zero.** The single `/gsd-` string is `:195`, a placeholder (`` `/gsd-foo` ``) inside an example changeset body |
| `.planning` references | 4 — `:370`, `:372`, `:679`, `:758` — **all** test-fixture context, never setup |
| Only acknowledgment GSD may be installed | `:1141`, and it is a *prohibition*: do not edit `.claude/agents/` |
| CONTRIBUTING's only AI-assistant instruction | `:176` — read `CONTEXT.md` + relevant ADRs, verify vocabulary before opening the PR |
| Delegated standards doc (`:168` → `docs/contributor-standards.md`) | No GSD-on-itself guidance either |

`docs/USER-GUIDE.md`, `COMMANDS.md`, `FEATURES.md`, `ARCHITECTURE.md` mention `/gsd-new-project` —
those are **product docs for GSD's users**, not contributor instructions.

**Decisive:** `.planning/` once existed here with the full scaffold and was deleted deliberately:

```
a52248cb  2026-02-08  chore: remove project-specific planning files
  .planning/PROJECT.md | REQUIREMENTS.md | ROADMAP.md | STATE.md | config.json   (-417 lines)
```

Not tracked on `next` today. **But `.planning/` IS gitignored** — `.gitignore:33`, under the heading
`# Internal planning documents`, alongside `reports/`, `analysis/`, and
`docs/GSD-MASTER-ARCHITECTURE.md`. A local `.planning/` therefore never appears in `git status` and
cannot ride along in a PR.

> Correction: an earlier revision of this file claimed `.planning/` was **not** ignored. That came
> from running `git check-ignore -v .planning` against a **non-existent** directory — the pattern
> `.planning/` matches directories only, so it reported no match. Verify with a trailing slash
> (`git check-ignore -v .planning/`) or after the directory exists.
>
> This cuts the other way on intent: **you do not gitignore a directory you never expect to exist.**
> The maintainers removed `.planning/` from version control *and* kept an ignore rule for it — which
> anticipates a local, uncommitted `.planning/` rather than forbidding one.

> **Rule: do not run `/gsd-new-project` *inside this checkout*.** But GSD has a first-class
> mechanism for using its own workflow on a repo whose `.planning/` must stay out of the tree —
> see §0.1. `CONTRIBUTING.md` never mentions it; it lives in `docs/CONFIGURATION.md` and the
> workspace workflow.

### 0.1 The canonical mechanism: `/gsd-workspace --new`

`commands/gsd/workspace.md` — "Create an isolated workspace with repo copies and **independent
`.planning/`**". Resulting layout (`gsd-core/workflows/new-workspace.md` §6-§8):

```
~/gsd-workspaces/<name>/        ← workspace root = the GSD project root
├── .planning/                  ← independent, OUTSIDE every repo        (§8)
├── WORKSPACE.md                ← manifest: repos, branches, strategy    (§7)
└── gsd-core/                   ← git worktree of your clone             (§6)
```

- Default base `~/gsd-workspaces` — `gsd-core/bin/lib/init.cjs:2545`, `src/init.cts:3019`
- Default strategy is **worktree** (`git worktree add "$TARGET_PATH/$REPO_NAME" -b "$BRANCH"`),
  which shares `.git` objects with your existing clone and creates the branch for you.
  `--strategy clone` is the alternative.
- Then `cd ~/gsd-workspaces/<name> && /gsd-new-project` — **at the workspace root, never in the repo.**

`git status` inside the worktree never sees `.planning/`; it is a sibling, not a child.

**Supporting configuration** (all `docs/CONFIGURATION.md`):

| Key | Line | Effect |
|---|---|---|
| `planning.sub_repos` | `:470`, `:472-481` | `gsd-tools` invoked *inside* a child repo walks up to the parent owning `.planning/` (≤10 ancestors, never above `$HOME`) |
| `--project-dir <path>` | `:481` | Explicit project root; idempotent under the walk-up |
| `GSD_PROJECT` | `:1687` | Env override of project root (v1.32) |
| `planning.commit_docs` | `:468` | Whether `.planning/` is committed. Auto-`false` if `.planning/` is gitignored (`:485-487`) |

**Ranked for a gsd-core contributor:**

1. **`/gsd-workspace --new`** — zero footprint in the checkout. Use this.
2. **`GSD_PROJECT` / `--project-dir`** — external project root without restructuring; you must
   remember to set it every session.
3. **In-repo `.planning/`** — now the simplest option, since `.gitignore:33` already ignores it. The
   directory lives in the checkout but never shows in `git status`. Per `docs/CONFIGURATION.md:485-487`,
   `commit_docs` auto-resolves to `false` when `.planning/` is gitignored, so GSD will not try to
   commit planning artifacts. Set `planning.commit_docs: false` explicitly anyway rather than relying
   on the auto-detection, which is cheap insurance.

**Practical caveat:** a worktree gets its own empty `node_modules`. Re-run `npm ci` (and the Node 22
activation) inside `~/gsd-workspaces/<name>/gsd-core/` before testing there.

### 0.2 There IS a canonical guide — it just never names this repo

`docs/issue-driven-orchestration.md` (182 lines, **"Status: stable workflow guide"**) documents
exactly the loop a gsd-core contributor needs:

> *"Audience: developers who track work in GitHub Issues, Linear, Jira, or similar issue trackers and
> want to drive AI-assisted implementation through GSD's existing primitives."*
> Loop: **issue tracker → workspace → plan/execute → verify/review → PR**, via `/gsd-workspace --new`,
> `/gsd-manager`, `/gsd-autonomous`, `/gsd-verify-work`, `/gsd-review`, `/gsd-ship`.
> *"It is documentation only. No new commands… every command referenced below already exists."*

gsd-core **is** an issue-driven repo — the issue-first rule is its central policy. The guide is
therefore directly applicable; it simply never says "you can do this on gsd-core."

**The strongest corroboration:** `docs/ship-pr-body-sections.md` documents the **TDD Audit** section
that `/gsd-ship` always appends to a generated PR body. It walks `merge-base..HEAD` (merges excluded),
reads each commit's `gate_status:` git trailer (`skill` | `fallback` | `exempt`), and **pairs each
`test:` commit with its following `feat:`/`fix:` implementation commit in a table**, counting
untrailered commits as `missing`.

That is a machine-generated proof of exactly the RED→GREEN commit discipline that
`docs/contributor-standards.md:198-206` makes a merge gate (§8). The tool and the standard fit
perfectly — **no document connects them.**

**Bottom line:** the capability, the workflow guide, and the merge gate all exist and align. The
missing artifact is a single sentence in `CONTRIBUTING.md` pointing at them. Plausible issue material
(docs), and the kind of gap the maintainers' own `[proposed]`/cross-reference-check discipline
(`contributor-standards.md:208-214`) is meant to catch.

---

## 1. Hard gates — these close or fail a PR

| Rule | Line | Consequence |
|---|---|---|
| **Issue first, always.** Fix → `confirmed-bug`; enhancement → `approved-enhancement`; feature → `approved-feature`. No code before the label. | `:42`, `:54`, `:58`, `:70`, `:75`, `:107-115` | PR closed without review |
| **Link with a closing keyword** — `Closes #N` / `Fixes #N` / `Resolves #N` in the body | `:182` | CI fails, auto-closed |
| **PR title** `type(#<digits>): summary` — type first, issue number in the *scope* | `:233-258` | `pr-title-validator.yml` fails on open/edit |
| **No draft PRs** | `:180` | Auto-closed |
| **Correct PR template** (separate Fix / Enhancement / Feature) | `:181` | Rejection reason |
| **One concern per PR**; no drive-by formatting | `:183-184` | Asked to split |
| **Scope must match the approved issue** | `:187` | Extra changes removed or re-issued |
| **Never edit `CHANGELOG.md`** — drop a `.changeset/` fragment | `:191-200` | Guaranteed merge conflict |
| **Changeset required** when touching `bin/`, `gsd-core/`, `src/`, `agents/`, `commands/`, `hooks/`, `sdk/src/` | `:202` | `Changeset Required` fails |
| **Docs required** when a fragment is typed `Added`/`Changed`/`Deprecated`/`Removed` | `:262-283` | `Docs Required` fails |
| **CI matrix must be green.** Node 22 floor, 24 primary, 26 forward-compat | `:186`, `:858-866` | Blocks merge |
| **Don't bundle test-fixture fixes into `docs:` commits** — the hotfix cherry-pick filter routes by subject prefix; a stale assertion under `docs:` is invisible to the picker (v1.42.3 / #3621) | `:185` | Ships a half-state to hotfix |

**Branch targets** (`:119-155`): everything → `next`. Exceptions: `fix/critical-NNN-*` → `main`;
`release/X.Y.0` and `hotfix/X.Y.Z` → `main` (created by `release.yml`, never by hand);
regression fix during an RC → `release/X.Y.0`.

Wrong base is cheap — the `PR Target Validator` comments and you edit the base in place.

---

## 2. Local configuration guidance

### Toolchain
| Line | Guidance |
|---|---|
| `:11` | `nvm use` — activate the `.nvmrc` pin (`22`) |
| `:14` | `npm run check:env` before anything |
| `:17`, `:23-24` | `npm ci` **required** over `npm install` — fails fast on lockfile drift, intentional |
| `:26` | `docs/contributing/bootstrap.md` is the **source of truth** for setup |

### Git (all explicitly optional and local)
| Line | Guidance |
|---|---|
| `:994-1009` | `.githooks/pre-commit` + `git config core.hooksPath .githooks` |
| `:1011-1049` | `.githooks/pre-push` blocking a private author-email pattern |
| `:1015` | `export GSD_BLOCKED_AUTHOR_REGEX='…'` in your shell profile |

> The committed `.githooks/pre-commit` runs **ten** generated-artifact freshness checks
> (alias-drift, state-document, configuration, workstream-inventory, project-root, plan-scan,
> secrets, schema-detect, decisions, workstream-name-policy). Without `core.hooksPath` set they are
> **inert** — every one is a CI failure you'd otherwise find after pushing.
>
> Known doc/hook drift: the hook matches `gsd-core/bin/lib/command-aliases.cjs`; `:1003` documents
> `command-aliases.generated.cjs`. Possible issue material; not chased.

### Environment variables
| Line | Guidance |
|---|---|
| `:204-207` | `GITHUB_BASE_REF=next node scripts/changeset/lint.cjs` — **without it the lint silently passes** on a PR CI will fail |
| `:1015` | `GSD_BLOCKED_AUTHOR_REGEX` |

### Per-PR metadata on GitHub
Labels: `confirmed-bug` `:42` · `approved-enhancement` `:54` · `approved-feature` `:70` ·
`no-changelog` `:210` · `no-docs` `:289`.

### In-repo files you configure per PR
| Line | File / marker |
|---|---|
| `:191-200` | `.changeset/<adj>-<noun>-<noun>.md` via `npm run changeset -- --type <T> --pr <N> --body "…"` |
| | Types: `Added` `Changed` `Deprecated` `Removed` `Fixed` `Security` |
| `:290` | `<!-- docs-exempt: <reason> -->` on its own line; empty reason is **rejected** |
| `:939-947`, `:961-969` | `tests/emitted-drift-acks/<your-issue>.md` — **new fragment per PR**, never the legacy file. Two sources may never name the same path. Delete your fragment when its last entry goes. |
| `:971-982` | `tests/emitted-drift-ack.json` must **never** persist on `next` — delete it, don't repair it |
| `:770-796` | `// allow-test-rule: <reason>` — standalone `//`, never inside `/** */`. 7 categories; `pending-migration-to-typed-ir` must cite an issue and is closed to new tests |
| `:512-521` | `// allow-spawn-timeout-ceiling: <reason>` — non-empty reason mandatory; only raises the ceiling for a call that already has a numeric timeout |
| `:649`, `:675` | `tests/fixtures/adversarial/<type>/`, `tests/fixtures/representative/<gate>/MANIFEST.json` |

### Maintainer-owned — read, never reconfigure
- `CONTEXT.md` (331 KB) and `docs/adr/` are canonical (`:163-176`). **Never load it wholesale and
  never paraphrase it.** Pull typed predicates with the selector, which parses the live file per call:
  ```bash
  node gsd-tools.cjs query context-predicates --class <CLASS> | --prefix <dotted.prefix> | --contains <text>
  ```
  `KEY.SUBKEY=value` predicates must be cited **verbatim by ID** — see §8.
- Never edit `.claude/agents/`, `.cursor/agents/`, `.github/agents/gsd-*` — install-sync outputs,
  silently overwritten. Fix drift with `bin/install.js`. Always edit `agents/`. (`:1141-1149`)

---

## 3. Test authoring rules

**Framework:** `node:test` + `node:assert/strict` only. **No Jest, Mocha, Chai.** (`:296-304`)
Suites are selected by filename suffix — `foo.security.test.cjs` → `security`; no suffix → `unit`. (`:298`)

**Cleanup:** `beforeEach`/`afterEach` for shared fixtures, or `t.after()` for per-test teardown.
**Never `try/finally` in a test body** — verbose, masks failures, not approved. (`:309-358`)

**Helpers** (`tests/helpers.cjs`): `createTempProject` · `createTempGitProject` · `createTempDir` ·
`cleanup` · `runGsdTools`. (`:360-374`)

**Subprocesses** go through `tests/helpers/process-seam.cjs` — `runNode` / `runGit` / `runHook`.
Never a hand-rolled `spawnSync`. Every call is timeout-bounded; branch on `outcome`, **never on
`signal`** (a timeout and a `maxBuffer` overflow are indistinguishable by signal). (`:376-418`)
Class-norm timeouts live in `tests/helpers/timeouts.cjs`. (`:420-426`)
Need a throw? `gitOrThrow` / `throwIfFailed`. Need the legacy shape without a throw? `toLegacyResult`. (`:428-493`)

**Prohibited — source-grep** (`:730-768`): never `readFileSync` a source `.cjs` to assert a string
is present. Use the CLI behaviorally.

**Prohibited — raw text matching on any produced text** (`:798-856`): no `.includes()`,
`.startsWith()`, `assert.match()` on file content, stdout, stderr, or free-form `reason` strings.
Production must expose a typed IR (frozen enum, `--json` mode, pure builder) and the test asserts on
that. **Wrapping the grep in a parser-looking function is still grep.** (`:843-845`)

**Fixture provenance (#2371)** (`:669-675`): a gate's fixtures may not derive from the gate's own
writer, grammar, or docstring examples. For a known-broken gate, record both `expected*` and
`currentBuggyOutput` in the manifest and assert against `currentBuggyOutput` — **never** `{ todo: true }`
or `skip`, because this repo's runner only understands `pass`/`fail` and counts a todo as a failure.

**QA matrix** (`:597-728`) — apply the cases that match the risk: happy path · missing · empty ·
whitespace-only · malformed · out-of-range · duplicate/conflicting · hostile · filesystem failure ·
concurrency/retry · cross-platform path/newline · regression fixture from the linked issue.
Specialized matrices for CLI routing (`:620`), parsers (`:647`), filesystem/installers (`:677`),
security & prompt injection (`:696`), generated files & parity (`:713`).

**Tests by contribution type** (`:1070-1080`): **Bug fix → regression test is required, written
first, must fail before the fix.** Enhancement → cover the new behavior and update stale tests.
Feature → success path plus at least one failure scenario. Behavior change → update or replace the
tests asserting the old behavior; a passing-but-wrong test is worse than none.

---

## 4. Code style & security

- **CommonJS** `.cjs` — `require()`, not ESM. (`:1101`)
- **No external deps in core** — `gsd-tools.cjs` and lib files use Node built-ins only. (`:1102`)
- **Conventional commits** — `<type>(<scope>): <subject>`, subject ≤72 chars, lowercase, imperative,
  no trailing period. Issue number goes in the scope: `fix(#1520): …`. (`:1103`)
- **Path validation** — `validatePath()` from `security.cjs` for any user-provided path. (`:1153`)
- **No shell injection** — `execFileSync` (array args) over `execSync`. (`:1154`)
- **No `${{ }}` in GitHub Actions `run:` blocks** — bind to `env:` first. (`:1155`)
- **Input validation checks shape, not just type** — `typeof === 'string'` is insufficient when the
  contract requires a format (ADR-227). (`:1095-1097`)
- **English only** in `docs/` and root `README.md`; translated READMEs are community-maintained. (`:277-279`)

---

## 5. Local verification sequence

Run before every push:

```bash
env -u GSD_AGENTS_DIR npm test          # see §6 — the env scrub is mandatory on this machine
npm run lint:ci                         # the 20-linter chain CI actually runs (not bare `npm run lint`)
GITHUB_BASE_REF=next node scripts/changeset/lint.cjs   # silently passes without the env var
npm run check:alias-drift               # if you touched command-manifest / alias files  (:924)
npm run regen:derived                   # if you touched a committed derived artifact    (:991)
```

`npm run regen:derived` covers `sync-manifest-versions`, the ADR index, the capability matrix, the
inventory manifest, the registry, and `tests/fixtures/install-tree/*.json`. Editing *shipped content*
(`gsd-core/workflows/*.md`, agents, commands) requires **no** regeneration — there is no committed
path→hash manifest. (`:929-992`)

**Docker parity** (`:910-917`, `:205-226`): `gsd-test-summary` runs the suite in a Linux container.
Default rule for code changes — both `Mac:` and `Docker:` lines must read `0 failed` before opening a
PR. Doc-only PRs are exempt; say so explicitly in the PR body.

---

## 6. This machine's gotchas (CI cannot see these)

Verified 2026-08-07 on `next` @ `343835fa`:

| Environment | Failures |
|---|---|
| As-is | 13 / 26183 |
| `env -u GSD_AGENTS_DIR npm test` | 3 / 26062 |
| `+ isolated HOME` | **1** — the only real one |

1. **`GSD_AGENTS_DIR` — 10 false failures.** `~/.zshenv:5` exports it, and `.zshenv` is sourced by
   *every* zsh invocation, so it reaches test child processes and shadows runtime-aware agent-dir
   resolution (Codex / OpenCode / Kimi / Trae). **Do not delete the export** — GSD-as-installed-tool
   needs it. Scrub per run: `env -u GSD_AGENTS_DIR npm test`.
2. **`~/.gemini/antigravity-cli` exists — 2 false failures.** The antigravity descriptor probes
   `["antigravity","antigravity-ide","antigravity-cli"]` and falls back to first-existing
   (`dcceb1a0` / #1441), so `getGlobalConfigDir('antigravity')` returns the `-cli` variant where
   `tests/install.test.cjs:106` expects the bare default.
3. **The one genuine failure.**
   `tests/fix-2658-trae-runtime-detection-and-instruction-path.test.cjs:210` asserts no emitted
   `.md`/`.js`/`.cjs` contains `.claude/.trae/rules`. `CHANGELOG.md:97` contains that literal string
   once — in prose describing the #2658 fix. The installer copies `CHANGELOG.md` into
   `.trae/gsd-core/`, so the changelog entry documenting the bug trips the test verifying it fixed.
   Likely fix: exclude `CHANGELOG.md` from the scan. **Not filed** — needs `confirmed-bug` first.

**Baseline: exactly 1 failure.** A change producing only that introduced nothing.

---

## 7. Notable absences in CONTRIBUTING.md

- **Zero Claude Code configuration guidance.** `.claude` appears 3× — `:679` (fault-injection target
  in tests), `:1145`/`:1149` (do-not-edit). No `CLAUDE.md`, `AGENTS.md`, or `.claude/settings*` guidance.
- **No mention of `.clinerules` or `GEMINI.md`**, though both exist at repo root.
- **No editor/IDE guidance** — `.editorconfig` exists but is never referenced.
- **"skill" appears twice** (`:274`, `:954`), both about gsd-core's *shipped* skills.

Because there is no maintainer position here, local Claude configuration cannot contradict one — and
`.gitignore:7` (`CLAUDE.md`) + `:12` (`.claude/`) keep it out of every diff.

**But CONTRIBUTING.md is not the whole story.** Two authoritative documents it barely references
carry rules that are merge gates — see §8 and §9.

---

## 8. AI-agent-assisted work — `docs/contributor-standards.md` §150-236

`CONTRIBUTING.md:168` delegates here in a single line. This is the binding standard for how you and
any AI assistant work on this repo. **None of it appears in CONTRIBUTING.md.**

| Requirement | Line |
|---|---|
| AI assistance is allowed for **every** contribution type. The correctness/review bar does not change because code was AI-assisted. | `:154` |
| Before an agent writes any code or docs it must read: **`CONTEXT.md` in full**, the relevant ADRs, and the approved issue scope. When dispatching an agent, put those reads in its prompt **explicitly**. | `:158-164` |
| An agent that invents synonyms for `CONTEXT.md` vocabulary, or contradicts an accepted ADR without flagging it, **has failed the pre-work requirement**. | `:164` |
| `CONTEXT.md` `KEY.SUBKEY=value` predicates must be cited **verbatim by ID, never paraphrased** (`META.RULE.brief-must-cite-doc`, `META.RULE.brief-no-paraphrase`). Pull them with `node gsd-tools.cjs query context-predicates --class \| --prefix \| --contains`. | `:166-176` |
| **PR body must state which ADR or standards section was followed** — the author's responsibility, not the agent's. | `:178` |
| **Worktree isolation is mandatory for agent-written code:** `git worktree add ../my-feature-worktree fix/NNNN-short-description`. Never commit agent output straight to `main` or an already-open feature branch without review. | `:180-188` |
| Model selection: **Sonnet** for implementation, tests, docs, triage. **Opus** for ADR authorship (maintainer only), cross-cutting refactors, adversarial review of complex PRs. Prefer a domain specialist agent over general-purpose. | `:190-196` |
| **TDD is a merge gate** for any Behavior-Adding Task: **RED** (commit a failing test naming the behavior) → **GREEN** (minimum implementation) → **REFACTOR**. **Commit each phase separately.** A PR with no failing-test commit for new behavior will be asked to add one. | `:198-206` |
| Adversarial self-review before opening: read each changed section as a hostile reviewer; mark aspirational text `[proposed]`; verify **every** cross-reference (path, ADR number, CONTEXT.md term) resolves on disk. | `:208-214` |
| CR-loop: fix in a **new commit, never amend a pushed commit**. Resolve threads via `gh api graphql -f query='mutation { resolveReviewThread(input:{threadId:"PRRT_..."}) { thread { isResolved } } }'` — not a reply comment, not auto-resolve. Address findings claim-by-claim. | `:216-227` |
| `## Standards followed` block in issue/PR bodies — **`[proposed]` only, not yet a gate** (#3232). | `:229-236` |

> **This is stricter than CONTRIBUTING.md:1074.** CONTRIBUTING says a bug fix needs a regression test
> that would fail without the fix. This says the failing test must exist as **its own commit, before
> the implementation** — visible in history, not just true at the end.

### 8.1 Three AI-guidance surfaces that disagree

| File | Tracked | Says | Assessment |
|---|---|---|---|
| `docs/contributor-standards.md` | yes | Ordinary git/TDD/PR flow. **No GSD workflow commands at all.** | **Authoritative** — CONTRIBUTING.md delegates to it |
| `.clinerules` (27 lines) | yes | *"Never Edit Outside a GSD Workflow. Do not make direct repo edits. All changes must go through `/gsd:plan-phase` → `/gsd:execute-phase` → `/gsd:verify-work`."* | **Suspect.** Added `5f3d4e61` 2026-04-03 by *"feat: add Cline runtime support via .clinerules (#1605)"* — **two months after** `.planning/` was deleted (`a52248cb`, 2026-02-08). Prescribes workflows against state that does not exist. Reads as a runtime-support artifact, not considered guidance. |
| `GEMINI.md` (55 lines) | yes | *"Treat `.planning/` as the source of truth — read it before acting."* | **Same defect** — no `.planning/` exists |

`.clinerules` does carry accurate coding standards (CommonJS only, no external deps in core,
`node:test` only, `execFileSync` over `execSync`, `validatePath()`) — those agree with CONTRIBUTING.md.
It is only the "never edit outside a GSD workflow" rule that is unsupported.

### 8.2 `.coderabbit.yaml` is provably stale

It disables CodeRabbit's ESLint tool with the rationale *"The repo intentionally does not use ESLint
— it ships its own targeted lint scripts (`scripts/lint-no-source-grep.cjs`, plus the `lint:tests`
npm script)."* Every particular is false:

| Claim | Verified reality |
|---|---|
| Repo doesn't use ESLint | `eslint.config.mjs` is 24 KB; `npm run lint` = `eslint . --cache …` |
| `scripts/lint-no-source-grep.cjs` | Does not exist — the rule is `eslint-rules/no-source-grep.cjs` |
| `lint:tests` npm script | Does not exist |
| "would add an external dependency (no external deps in core)" | That rule governs **core runtime**, not devDependencies |

Consequence: the AI reviewer has ESLint off for reasons that expired. Possible issue material.

---

## 9. Testing standards beyond CONTRIBUTING.md — `TESTING-STANDARDS.md`

Root file, 188 lines, **not referenced anywhere in CONTRIBUTING.md**. Authoritative for test
correctness contracts and ADR-456 policies. CONTRIBUTING.md covers imports, setup/teardown, fixture
formatting and the QA matrix; this covers whether a test is *worth anything*.

### The six test-rigor contracts (`:14-84`)

1. **Exercise real code, not source or output text** — call exported functions or run the CLI and
   parse structured output. No `readFileSync` + text assert; no asserting raw stdout/stderr beyond
   exit code. Enforced by `local/no-source-grep`.
2. **No vacuous-truth assertions** — an assertion must be *capable of failing* given a plausible
   defect. `assert(true)`, or `assert.ok(x)` where `x` is unconditionally set above, adds nothing.
3. **No pass-always tests** — a test that passes whether or not the feature exists is **worse than no
   test**. Write it first, confirm it fails against a stub, then implement.
4. **Test the claimed path** — if the name says `acquireLock expires after TTL`, the body must call
   `acquireLock`, not a stub that replaces the SUT.
5. **Complete mocks** — mock the dependency (filesystem, network, clock), never the SUT's own logic.
   A mock returning a hardcoded value from inside the function under test is a pass-always test in disguise.
6. **Counter-tests for negative space** — every behavioral contract needs ≥1 test of an input the SUT
   should reject or treat differently. Enforced partly by `no-only-tests`.

### ADR-456 policies (`:88-164`)

- **No timing / elapsed-time assertions.** `assert(Date.now() - start < 200)` tests the host machine,
  not the code, and flakes on loaded CI. Rule: `local/no-elapsed-assertion`.
- **Clock-seam pattern for concurrency.** Inject a clock (`function acquireLock(res, { clock = Date } = {})`)
  and drive it with `t.mock.timers.enable(['Date'])` / `setTime` / `tick`. **Real OS scheduler races
  are not a permitted test pattern.** Rule: `local/no-magic-sleep-in-tests` bans `setTimeout`/`sleep`/`delay`
  inside test bodies.
- **Property-based testing tier.** Modules doing parsing, transformation, budget/limit logic, or any
  bijective contract need ≥1 `fast-check` property test asserting a domain invariant (round-trip,
  monotonicity, boundary containment, idempotency). Lives in the normal `*.test.cjs`, no suite tag.
- **Mutation testing — 80% threshold.** Stryker runs `--since origin/next` on the ubuntu / Node 24 leg
  as a **PR gate**. Below 80% you must kill the surviving mutants or add the path to
  `stryker.config.mjs` with a documented reason. *"A surviving mutant is a concrete specification of
  missing coverage. Treat it as a failing test, not as a metric."*
- **Delete-bad-tests policy.** These are **deleted and replaced in the same PR** — never commented
  out, skipped, or given a permanent `allow-test-rule`: pass-always · vacuous-truth · source-grep ·
  elapsed-time · real-race · permanent `allow-test-rule` with no tracking issue.

### ESLint rule reference (`:168-181`)

| Rule | Severity | Catches |
|---|---|---|
| `local/no-source-grep` | `warn` → `error` (#453) | `readFileSync` on source + text assertions; `assert.match` on raw stdout/stderr |
| `local/no-magic-sleep-in-tests` | `warn` → `error` (#453) | `setTimeout`/`sleep`/`delay` inside test bodies |
| `local/no-elapsed-assertion` | `warn` → `error` (#453) | `Date.now()` deltas, `process.hrtime()`, `performance.now()` comparisons |
| `no-only-tests/no-only-tests` | `error` | `.only` committed to non-scratch files |
| `no-restricted-syntax` ×2 | `error` | Top-level `setTimeout`; `.only` member access |

> The three `local/*` rules ship at `warn` today. **New violations are out of policy regardless of
> the current ESLint severity** (`:179`) — a passing lint is not permission.

---

## 10. Where guidance actually lives (doc map)

| Topic | Authority |
|---|---|
| Process, gates, PR/branch rules | `CONTRIBUTING.md` |
| **AI-agent work, TDD commits, worktrees, CONTEXT.md citation** | **`docs/contributor-standards.md` §150-236** |
| **Test rigor, mutation gate, delete-bad-tests** | **`TESTING-STANDARDS.md`** |
| Environment setup | `docs/contributing/bootstrap.md` |
| Cross-platform lint rules | `docs/contributing/cross-platform-portability-rules.md` (17 KB), `adding-a-portability-rule.md` |
| Suite naming, CI matrix, size budgets | `docs/TESTING-SUITES.md` |
| Worked test examples | `TEST-EXAMPLES.md` |
| Branch model | `docs/branching.md`, `docs/branch-protection.md` |
| Config keys, `GSD_PROJECT`, `sub_repos`, workspaces | `docs/CONFIGURATION.md` |
| Changeset format | `.changeset/README.md` |
| ADR conventions | `docs/adr/README.md`, `docs/contributor-standards.md` §59-149 |
| Versioning | `VERSIONING.md` · Security policy: `SECURITY.md` |

**Enforcement surface:** 15 of `.github/`'s 24 workflows are pure contributor policy —
`require-issue-link`, `auto-close-unsolicited-prs`, `close-draft-prs` (+ sweep), `pr-title-validator`,
`pr-target-validator`, `pr-template-format`, `branch-naming`, `changeset-required`, `docs-required`,
`duplicate-check` (+ sweep), `dismiss-unauthorized-pr-approvals`, `version-gate`, `auto-label-issues`.
Plus 5 issue templates, 4 PR templates + default, `CODEOWNERS`, 3 rulesets.
