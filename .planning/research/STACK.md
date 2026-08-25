# Stack Research — v1.12 defect-fix tooling

**Domain:** Tooling additions for a mature TypeScript/Node CLI toolchain (gsd-core 1.11.0, faffi fork)
**Researched:** 2026-08-24
**Confidence:** HIGH (every load-bearing claim below is either a doc citation or a measurement run in this repo today)
**Scope:** ONLY the three defect classes with a tooling dimension. The existing stack
(TypeScript `src/*.cts` → `gsd-core/bin/lib/*.cjs`, Node >=24, `node:test`, ESLint + `local/*`
AST rules, markdown-authored agent fences) is **not** under review and is **not** proposed for
replacement anywhere in this document.

> **Revision note — this file supersedes an earlier draft.** A first pass recommended
> `sh-syntax` on the strength of its zsh support. **Probe D (below) reversed that**: its JSON AST
> is positional-only and no lint rule is writable against it. If you are holding a copy that
> recommends `sh-syntax` — e.g. the snapshot at `.planning/.cache/research-backup/STACK.md.orig`
> — it is superseded by this one. The reversal is *not* a change of opinion; it is a measurement.

---

## Headline

**Two of the three questions need zero new dependencies. One needs two devDependencies, both MIT
and both dev-only.**

| # | Class | Verdict | New dependency |
|---|---|---|---|
| 1 | Shell-fence portability | Split: execution harness = no new dep; static lint = **two devDeps** (a real bash CST parser) | `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1` (dev only) |
| 2 | Subprocess lifecycle | Stdlib only — and the correct answer is "do not create a process tree", not "kill one" | none |
| 3 | CI blindness / invariant deletion | Three layers, all built from primitives already in `devDependencies` | none |

**Headline do-NOT-add, so it survives summarisation:** `shellcheck` (no zsh dialect in any
release, and structurally blind because all six mechanisms are *valid bash*); `sh-syntax` /
`mvdan-sh` (**they do parse zsh — that is not the objection** — their JSON AST is positional-only
and cannot express a rule); `bash-parser` (unmaintained since 2017); `tree-sitter-bash`'s *native*
binding (needless native compile — use the `.wasm` from the same tarball); any regex-per-mechanism
lint (ADR-1703). Full reasoning in "What NOT to add (Q1)".

**Why a bash-only grammar is the right call, stated up front because it looks wrong:** the
objection "a bash-only parser is blind to valid bash that behaves differently under zsh" is true
of a bash-only *linter* with a fixed rule set (shellcheck) and false of a bash-only *parser*. The
parser's only job is to locate `${ARR[0]}` / `BASH_REMATCH` / `read -ra` in the source; the
knowledge that zsh 1-indexes, populates `$match`, and rejects `read -a` lives in the **rule**. All
seven mechanisms are written in bash and are found in the bash parse — verified node-by-node in
"Verified: every rule is directly expressible". A zsh grammar would add nothing, and the one
Node-reachable zsh parser cannot host a rule at all.

Nothing proposed here touches generated `gsd-core/bin/lib/*.cjs`. The one production change
(Q2) lands in `src/prohibition-enforcement.cts` and is picked up by `npm run build:lib`.

---

## Evidence gathered for this report (measured today, in this tree)

Every recommendation below rests on a probe run against this repo's own corpus, not on recall.

**Probe A — fence syntax-parse rate.** 1052 shell-tagged fences extracted from `agents/`,
`gsd-core/workflows/**`, `gsd-core/references/`, `commands/**`, `skills/**` (431 files), each
written to a temp file and run through `-n` (parse-only):

| Parser | Parsed | Rate |
|---|---|---|
| `/bin/bash` 3.2.57 (macOS system bash) | 1035 / 1052 | 98.4% |
| `/bin/zsh` 5.9 | 1033 / 1052 | 98.2% |
| `/bin/sh` | 1031 / 1052 | 98.0% |

**Probe B — the same corpus through `sh-syntax@0.6.0` (WASM `mvdan/sh` v3.13.1):**
`LangBash` 1027/1052 (97.6%), `LangZsh` 1030/1052 (97.9%).

**Probe C — the same corpus through `web-tree-sitter@0.26.13` + `tree-sitter-bash@0.25.1`:**
**1033 / 1052 (98.2%) parse with no `ERROR` node.**

**What the failures actually are.** All 17 `bash -n` failures are *illustrative pseudo-code*, not
executable fences — `<files the fix touched>` placeholder argv, `Task(subagent_type=…)` /
`Glob("…")` tool-call syntax. Of the 8 fences `sh-syntax` rejects that `bash -n` accepts,
**6 are `${a.b}`-shaped prompt interpolation** (e.g. `gsd-core/references/loop-hook-dispatch.md:55`
`gsd_run ${ref.command} …`, which zsh itself rejects at parse time with `bad substitution`),
1 is a heredoc split by fence extraction, 1 is a `$((`-vs-`$( (` ambiguity.

**Probe D — AST usability.** Both candidate parsers were fed the real defect shapes and their
output inspected. This probe **reversed** the initial recommendation; see Q1(b).

---

## Q1 — Shell-fence portability

The six divergences (1-indexed arrays, NOMATCH aborting glob assignment, no `PIPESTATUS`, no
`BASH_REMATCH`, no `read -a`, no word-splitting on bare `$VAR`) split cleanly into two problems
with two different answers.

### (a) Execute the same fence under bash 3.2.57, zsh 5.9 and POSIX `sh`

**Recommendation: no new tool. Parameterize the existing seam, and add a macOS CI lane.**

| Change | File:line | Why |
|---|---|---|
| Parameterize `runBashScript()` over a shell list | `tests/unreachable-shell-guard.test.cjs:144-149` | Line 148 hardcodes `#!/usr/bin/env bash` and line 149 passes `{ interpreter: 'bash' }`. This is the single point where the harness binds to a shell the deployment never uses. |
| **Pass ABSOLUTE interpreter paths** — `/bin/bash`, `/bin/zsh`, `/bin/sh` | same | ⚠ Non-obvious and load-bearing. `interpreter: 'bash'` is a bare name resolved through `PATH`. On GitHub's macOS runners **Homebrew bash 5.x sits ahead of `/bin/bash` on `PATH`**, so a lane passing `'bash'` silently tests 5.x and covers nothing the ubuntu lane does not — reproducing the exact defect being fixed ("the harness binds to a shell the deployment does not use"). Probes A and C above used absolute paths for this reason. |
| No change needed to the spawn primitive | `tests/helpers/process-seam.cjs:235-241` | `runHook`'s `interpreter` is **already an explicit parameter**, and the JSDoc at :221-223 states it is *"EXPLICIT, never inferred from `target`'s extension"*. Passing `/bin/zsh` or `/bin/sh` is a supported call, not a new capability. Satisfies `local/no-unbounded-spawn` with no allowlist. |
| Add a macOS lane (or a narrow `shell-fences` job) | `.github/workflows/test.yml:158-210` (matrix `include:`) | **The matrix is `ubuntu-latest` + `windows-latest` only — there is no macOS lane in `test.yml` at all.** |

**Why the CI change is unavoidable and is a *workflow* change, not a tool choice:**

- bash **3.2.57** exists only on macOS (GPL-3 licensing); `ubuntu-latest` ships bash 5.x. The
  stated compatibility contract (`PROJECT.md` Constraints) names bash 3.2.57 explicitly, so the
  bash half of the contract is untestable on the current matrix regardless of zsh availability.
  *Corollary: do not spend time determining whether zsh is preinstalled on `ubuntu-latest` — it
  is not decision-relevant.*
- `windows-latest` has neither bash nor zsh. The shell-fence job must be macOS-gated, never
  matrix-wide, or it reds the Windows shards.
- **Precedent exists in this repo:** `.github/workflows/install-smoke.yml:76-79` already runs
  `os: macos-latest` with `shell: 'zsh {0}'`.

⚠ **DO NOT copy `full_only: true` from that precedent** (`install-smoke.yml:75`). That flag makes
the macOS entry skip on `pull_request` events (see the skip step at `:84-88`). A fence lane that
does not run on PRs is exactly the condition under which upstream's four fix rounds
(#2770 → #2962 → #3300 → #3409) each shipped clean while the defect survived. The fence lane must
be a required PR lane.

**POSIX `sh` caveat the roadmapper needs before adding an `sh` lane.** Probe A found 4 fences
that parse under bash/zsh but fail `/bin/sh -n`, all on process substitution `< <(…)`
(`code-review-fix.md:159`, `code-review.md:373`, `complete-milestone.md:67`,
`reapply-patches.md:138`). The fix currently chosen in the todo —
`while IFS= read -r f; do cat "$f"; done < <(find …)` — **is one of these**: process substitution
is a bash/zsh extension, not POSIX. `.planning/reference/shell-fence-portability.md`'s
"12/12 … **and POSIX `sh`**" row measured the *pipe* form (`find … | while read`), which is a
different construct with different loop-variable semantics. Resolve which form is being shipped
before deciding whether `sh` belongs in the shell matrix; the two cannot both be true.

### (b) Statically lint for the six divergences

**Recommendation: `web-tree-sitter` + `tree-sitter-bash`, driving a new AST lint in the
`scripts/lint-*.cjs` family.**

| Package | Version | Purpose | Why |
|---|---|---|---|
| `web-tree-sitter` | `0.26.13` (2026-08-23) | Pure-WASM tree-sitter runtime | MIT, **zero dependencies**, no native build, dual CJS/ESM (`exports.require` → `web-tree-sitter.cjs`) |
| `tree-sitter-bash` | `0.25.1` (2025-12-02) | The bash grammar | MIT; **ships a prebuilt `tree-sitter-bash.wasm` (1.36 MB) inside the npm tarball** — the only file consumed |

#### The reframing that makes a bash-only grammar correct

The instinct is "we need a zsh parser because the bug is about zsh." That is wrong, and it is what
sent the first pass of this research down a dead end. **All six mechanisms are written in bash and
are detected in the bash parse.** The zsh knowledge lives in the *rules*, not the *parser*: the
lint finds `${ARR[0]}`, `BASH_REMATCH`, `read -ra`, `PIPESTATUS`, an array-assignment from a glob,
and a bare `$VAR` in a `for` word-list — all bash constructs — and the rule carries the knowledge
that zsh diverges on each. A zsh grammar would add nothing.

#### Verified: every rule is directly expressible

Measured today. Feeding the real defect shapes to `tree-sitter-bash` produces named fields and
exact source text for every one:

| Mechanism | Verified CST match | Emitted node (measured) |
|---|---|---|
| M1 NOMATCH abort | `variable_assignment` whose `value:` is an `array` containing a `word` with glob metacharacters; and `for_statement value:` of the same shape | `(variable_assignment name: (variable_name) value: (array (concatenation (string (simple_expansion …)) (word))))`, `word` text `«/*-CONTEXT.md»` |
| M2 `${ARR[0]}` | `expansion → subscript` with **named field `index:` typed `number`** | `(expansion (subscript name: (variable_name) index: (number)))` — and `${_CTX[@]}` is distinguishable, its `index:` is `(word)` text `«@»` |
| M3 `BASH_REMATCH` | `subscript name: (variable_name)` text `«BASH_REMATCH»` | confirmed |
| M4 `read -ra` | `command name: (command_name (word "read")) argument: (word "-ra")` | confirmed |
| M5 word-split on bare `$VAR` | `for_statement value: (simple_expansion (variable_name))` — **structurally distinct** from `(command_substitution)`, which is what makes the six retracted `$(…)` sites stay retracted | confirmed |
| M6 `PIPESTATUS` | `subscript name: (variable_name)` text `«PIPESTATUS»` | confirmed |
| M7 `grep -oP` (new, see below) | `command name: (command_name (word "grep")) argument: (word "-oP")` | same shape as M4 |

#### Why `sh-syntax` was evaluated first and then rejected

It is the more obvious candidate and it is the wrong one — recording this so a later phase does
not re-derive it.

`sh-syntax@0.6.0` is a WASM build of `mvdan/sh` v3.13.1, and `mvdan/sh` **v3.13.0 (2026-03-09)
genuinely added zsh**. These claims are post-training-cutoff, so each is sourced individually and
each is checkable without redoing the search:

| Claim | Source read | How to re-verify |
|---|---|---|
| v3.13.0 added zsh to the parser and formatter | `https://github.com/mvdan/sh/releases/tag/v3.13.0`, published 2026-03-09 — *"This release introduces support for [Zsh](https://www.zsh.org/) in the parser and formatter, which was tracked in issue #120."* | open the release page |
| v3.13.1 (2026-04-06) added further zsh fixes | `https://github.com/mvdan/sh/releases/tag/v3.13.1` — `[[zsh]]` EditorConfig support, `.zshrc` detection, four `$…` zsh parse fixes | open the release page |
| `LangZsh` exists, follows zsh 5.9, is experimental | `https://github.com/mvdan/sh/blob/master/syntax/parser.go` — *"LangZsh corresponds to the Z shell… its support in the syntax package is experimental and incomplete for now. See issue #120. We currently follow Zsh version 5.9."* | grep `LangZsh` in `syntax/parser.go` |
| `sh-syntax@0.6.0` pins `mvdan.cc/sh/v3 v3.13.1` | `https://raw.githubusercontent.com/un-ts/sh-syntax/main/go.mod` — `require ( … mvdan.cc/sh/v3 v3.13.1 )` | `curl` that URL |
| The published JS binding really exposes `LangZsh` | **Measured, not read.** `npm i sh-syntax@0.6.0` then `require('sh-syntax').LangVariant` → `{LangBash:1,LangPOSIX:2,LangMirBSDKorn:4,LangBats:8,LangZsh:16,LangAuto:32}`; `parse('echo ${(ps.:.)PATH}', {variant:16})` succeeds while variants 1/2/4 fail with *"parameter expansion flags are a zsh feature"* | re-run those two lines |

⚠ One trap for a reviewer re-checking this: **`src/types.ts` on sh-syntax's default branch is stale**
— it still shows the pre-bitset `LangBash:0 … LangAuto:4` enum with no `LangZsh`. Trust the
installed tarball's runtime export (measured above), not that file.

**It still fails, on one decisive measurement: its JSON AST is positional only.** Parsing
`echo foo` yields `Stmt.Cmd === { Pos, End }` — no node type, no `Args`, no literal values. The Go
`Command` interface is marshalled without a type discriminator, so `Word.Lit` comes back `""` and
`Word.Parts[0]` is a bare position pair. Its own README corroborates this: `print()` requires
`originalText` *"for now, hope we will find better solution later"* — because the AST cannot
reconstruct the source. **None of M1–M7 is writable against that output.** `sh-syntax` is a usable
*validator* (parse succeeds/fails per dialect — that is exactly how Probe B used it) and not a
usable *rule substrate*.

Reproduce in three lines:

```bash
npm i sh-syntax@0.6.0
node -e "require('sh-syntax').parse('echo foo').then(a=>console.log(JSON.stringify(a.Stmts[0].Cmd)))"
# → {"Pos":{"Offset":0,"Line":1,"Col":1},"End":{"Offset":8,"Line":1,"Col":9}}
```

No node type, no `Args`, no literal. Contrast the same input through `tree-sitter-bash`:
`(command name: (command_name (word)) argument: (word))`, with `.text` on every node.

#### Known limits — state them in the ADR, do not discover them in a phase

1. **`Parser.init()` and `Language.load()` are async.** Fine in a `scripts/lint-*.cjs` gate or a
   `node:test`. **Impossible inside an ESLint rule**, whose `create()` visitor is synchronous.
   This is the same limit `sh-syntax` had and it is why the lint's home is `scripts/`, not
   `eslint-rules/`.
2. **`tree-sitter-bash` declares `node-addon-api` + `node-gyp-build`** — those are for the
   **native** binding, which is never loaded here. CI already installs with
   `npm ci --ignore-scripts` (`.github/workflows/test.yml:100`), so nothing compiles. Load the
   `.wasm` by path; never `require('tree-sitter-bash')`.
3. **tree-sitter recovers rather than throws.** A malformed fence yields an `ERROR` node instead of
   an exception. The lint must treat `rootNode.hasError` as "needs a human", never as an automatic
   violation — 19 of 1052 fences hit this (Probe C), all pseudo-code.
4. The ~19 pseudo-code fences must be an **explicit, enumerated exclusion list** in the lint, not a
   wildcard skip — otherwise the list grows silently.

**Integration point.** A new `scripts/lint-shell-fence-portability.cjs`, wired into
`lint:ci` (`package.json:122`) next to the existing `lint-unreachable-guard-drift.cjs`, reusing
`scripts/lib/drift-scan.cjs` for the tree walk / root confinement / report sanitizing — which is
what ADR-3409 Decision 3 already requires of any new guard in this family (*"a guard that copies
the scanner turns the family into the ad hoc engine"*).

### The ADR conflict — name it, do not let a phase re-litigate it

Two accepted ADRs point opposite ways on this input, and both are cited in the todo's own notes.

- **ADR-1703** (`docs/adr/1703-portability-enforcement-architecture.md`): *"AST, not regex … stop
  parsing a language with regex; use the real parser"*; *"growing the regex path is the wrong
  direction (Kernighan's Law, Greenspun's Tenth Rule)."*
- **ADR-3409** (`docs/adr/3409-unreachable-shell-guard-arms.md:65`): *"No off-the-shelf linter fits
  the target — ESLint parses JS ASTs, `shellcheck` parses real shell, and this input is shell
  fragments inside markdown fences carrying `${}` prompt interpolation that is not valid shell."*

**Resolution, with the measurement that settles it:**

ADR-1703's **principle** holds and is *satisfied* by this recommendation — for shell-in-markdown,
"the real parser" is a shell parser, so a shell-CST lint is ADR-1703-compliant, not a violation.
ADR-1703's **mechanism** (an ESLint `local/*` rule) does **not** transfer: ESLint's configured
globs are `.cts`/`.cjs`/`.js`, markdown is not among them, and the parser init is async. Hence
`scripts/lint-*.cjs`, not `eslint-rules/`.

ADR-3409's **premise is empirically overstated and should be amended in this milestone.** Its
stated blocker — fences carrying interpolation that is not valid shell — is real but accounts for
**6 of 1052 fences (0.6%)** (Probe B). 97.6–98.4% of shipped fences parse as real shell under
four independent parsers, and tree-sitter parses 98.2% with no error node while emitting a fully
typed CST (Probes C and D). A 0.6% enumerable exclusion list is not grounds for rejecting a
parser; it is a config constant. Land the amendment alongside the lint so the next round does not
re-derive the same rejection.

Note also that ADR-3409's own phrasing is the tell: *"`shellcheck` parses real shell"* treats
"a linter with a fixed rule set" and "a parser you can write rules against" as the same thing.
They are not, and the distinction is the whole recommendation.

### What NOT to add (Q1)

| Avoid | Why — with citation | Use instead |
|---|---|---|
| **`shellcheck`** (v0.11.0, 2025-08-03) | Two independent kills. (i) **No zsh mode in any release.** `shellcheck.1.md`: *"`-s shell` … Valid values are `sh`, `bash`, `dash`, `ksh`, and `busybox`."* Wiki SC1071: *"ShellCheck only supports … bash, ksh, dash and POSIX sh … It does not support scripts written for other shells like Zsh."* The CHANGELOG records *"Zsh support has been removed."* (ii) The structural kill, which survives even if zsh support returned: **all six mechanisms are valid, correct bash**, and shellcheck is a fixed rule set, not a rule engine. It has no rule for "this correct bash behaves differently under zsh" and no way for you to add one. | `web-tree-sitter` + `tree-sitter-bash` |
| **`sh-syntax`** (npm 0.6.0) | Its JSON AST is **positional only** — `Stmt.Cmd` for `echo foo` serializes as bare `{Pos,End}`, `Word.Lit` is `""`. Measured. None of M1–M7 is expressible. Its README's *"`originalText` is required for now"* is the same limitation admitted upstream. Genuinely useful as a **zsh dialect validator** if a future need arises — it is the only maintained thing that parses zsh 5.9 from Node — but not as a lint substrate. | `web-tree-sitter` + `tree-sitter-bash` |
| **`shfmt`** as the linter | It is a formatter, not a linter — no rule engine to express M1–M6. (Its `-ln` flag *does* accept `zsh` as of v3.13.0, binary v3.13.1 — but the value is in the library underneath, which is what `sh-syntax` vendors, and that route is closed above.) | `web-tree-sitter` + `tree-sitter-bash` |
| **A Go helper binary using `mvdan/sh` directly** (full AST available in Go) | Adds a Go toolchain and a compiled artifact per OS to an npm-shipped project, on three CI lanes. Disproportionate; and ADR-1703 Alternative 4 already rejects a parallel tool. | `web-tree-sitter` + `tree-sitter-bash` |
| **`zsh -n` / `bash -n` / `bash --posix`** as the lint | Syntax-only. Every one of the six is **runtime** semantics (1-indexing at expansion, NOMATCH during word-expansion, empty `BASH_REMATCH`, `read -a` as a runtime option error). Measured coverage of the six: **0/6.** | Keep as a cheap CI pre-filter and as the feasibility probe it served as here (Probe A) — not as the detector |
| **A regex lint per mechanism** | Directly against ADR-1703, which was created *because* an attempted regex extension "silently could not match `deepStrictEqual`". Six regexes over 1052 fences reproduce the exact accretion ADR-1703 tore out. | one CST lint, seven rules |
| **`bash-parser`** (npm) | `0.5.0`, last published **2017-06-22**; 20 transitive runtime dependencies. Unmaintained, POSIX-only. | `tree-sitter-bash` |
| **`tree-sitter-bash`'s *native* binding** (`require('tree-sitter-bash')` + `tree-sitter`) | Pulls `node-addon-api` + `node-gyp-build` into a real compile on three CI OSes including `windows-latest`. Unnecessary — the `.wasm` in the same tarball needs no compile. | load `tree-sitter-bash.wasm` via `web-tree-sitter` |
| **`mvdan-sh`** (npm) | `0.10.1`, last published **2022-05-08**. GopherJS build predating `LangZsh`, ~4x slower than `sh-syntax` on the latter's own benchmark, and it inherits the same lossy-AST problem. | `tree-sitter-bash` |
| **`emulate -L sh` preamble across 902 fences** | Fixes 3 of 6 in one line but changes far more than three behaviours across every shipped fence; blast radius disproportionate to a fix PR, and `CONTRIBUTING.md:195` "one concern per PR" makes it unreviewable. | targeted per-site fixes + the lint as ratchet |
| **A standalone custom AST tool outside the `scripts/lint-*.cjs` family** | ADR-1703 Alternative 4 rejected exactly this: *"building a parallel tool repeats the original mistake."* ADR-3409 Decision 3 says the same for the guard family. | `scripts/lint-*.cjs` + `scripts/lib/drift-scan.cjs` |

### Bonus finding — a seventh mechanism, same class, found by Probe A

`grep -oP` / `grep -P` appears at **5 shipped-fence sites**: `gsd-core/workflows/pause-work.md:18,21,24`
and `gsd-core/workflows/sync-skills.md:33,40`. `-P` (PCRE) is a GNU grep extension; **BSD grep on
macOS rejects it**, so the captured variable is silently empty — the same
fails-in-the-safe-looking-direction shape as M1–M6, and precisely the class
`scripts/lint-portable-timeout.cjs` (#2351) exists to ban. It is expressible in the same CST rule
shape as M4 (see the table above). Worth adding as **M7** to
`.planning/reference/shell-fence-portability.md`.

---

## Q2 — Subprocess lifecycle (orphaned grandchild burning a core)

**Recommendation: no new dependency, no tree-kill, no async rewrite. Do not *create* a process
tree.** The todo's chosen fix is correct and the Node 24 docs confirm every step of it.

### The fix

`src/prohibition-enforcement.cts:220-222` — add `--test-isolation=none` to `buildNodeTestArgs`.
Compiled to `gsd-core/bin/lib/prohibition-enforcement.cjs` by `npm run build:lib`; **never
hand-edit the `.cjs`.**

Node v24 doc citations (CLI Options → Test Runner; `test.json` → execution model):

> `--test-isolation=mode` — *'process' runs each test file in a separate child process, while
> 'none' runs all tests in the same process. **The default is 'process'**… renamed from
> `--experimental-test-isolation` in v23.6.0.*

> *If isolation is disabled, **test files are imported into the main runner process**, which may
> allow tests to interact with shared global state across different files.*

So with `none` the hang runs **in the direct child that `execFileSync`'s `timeout` actually
signals** — which the todo already proved sufficient empirically (both orphans died on a plain
`SIGTERM`; no `SIGKILL` escalation needed).

Accepted side effect, documented: *"If `--test-isolation` is set to 'none', this flag
[`--test-concurrency`] is ignored and concurrency is set to one."* Irrelevant — every check spawns
exactly one file.

### Why a tree-kill is not merely undesirable but **unavailable at these call sites**

This is the constraint the roadmapper needs, because it decides the deferred sweep too.

- **`detached` is not a documented option for `spawnSync` or `execFileSync`.** The Node v24
  `child_process` page lists `spawnSync` options as `cwd, input, argv0, stdio, env, uid, gid,
  timeout, killSignal, maxBuffer, encoding, shell, windowsVerbatimArguments, windowsHide`, and
  `execFileSync` as `cwd, input, stdio, env, uid, gid, timeout, killSignal, maxBuffer, encoding,
  windowsHide, shell`. `detached` is documented **only** for `spawn()` and `fork()`.
- `process.kill(-pid)` requires the child to be a **process-group leader**, which is what
  `detached: true` creates (*"On non-Windows platforms, if `options.detached` is set to `true`,
  the child process will be made the leader of a new process group and session"*).
- Therefore **`detached: true` + `process.kill(-pid)` cannot be applied to a synchronous call site
  without converting it to async.** At a sync site there are exactly two cures: **remove the tree**,
  or **convert to async**. Nothing else.
- `options.signal` (AbortSignal) is likewise **async-only**, and even where available it aborts the
  direct child with `killSignal` (default `'SIGTERM'`) — one PID, not the group.
- Node documents the leak itself, in so many words, under `subprocess.kill()`:
  > *On Linux, child processes of child processes will not be terminated when attempting to kill
  > their parent.*
- **Windows has no documented answer.** Node says only that signals are ignored except
  `SIGKILL`/`SIGTERM`/`SIGINT`/`SIGQUIT` and the process is *"always killed forcefully and
  abruptly"*. The page says nothing about tree termination or `taskkill`. Any tree-kill would need
  a hand-rolled `taskkill /T /F` branch — an undocumented Windows divergence in a module where
  `windowsHide` and portability are already load-bearing.

### Static half — extend an existing rule, do not add a script

If a static check is wanted so the class cannot return, the home is the existing `local/*` plugin:
`eslint-rules/require-subprocess-timeout.cjs` and `eslint-rules/no-unbounded-spawn.cjs`. These are
`.cts`/`.cjs` surfaces, so ADR-1703's mechanism *does* apply here (unlike Q1). Extending one of
them is strictly cheaper than a new `scripts/lint-*.cjs`.

### The deferred sweep

The todo's own follow-up — *"worth a sweep for other `execFileSync`/`spawnSync` timeout sites that
assume the bound reaches the whole tree"* — is fully decided by the constraint above. For each site
found, the roadmapper's question is binary: **can the tree be removed (a flag, a direct invocation),
or must this site go async?** There is no third option and no library that supplies one.

### What NOT to add (Q2)

| Avoid | Why | Use instead |
|---|---|---|
| `tree-kill`, `terminate`, `ps-tree`, `fkill` | All require an async/`spawn` call site (or a shell-out) to obtain a process group; at a sync site they cannot help. Each also adds a Windows `taskkill` shell-out that Node does not document. | `--test-isolation=none` |
| `execa` | Bundles process management but is async-first; adopting it converts the module and imports a dependency tree into a package that ships with 2 runtime deps today. | stdlib `child_process` |
| A hand-rolled `detached` + `process.kill(-pid)` in `prohibition-enforcement.cts` | Unavailable without a `sync` → `async` conversion (see above); the sync, shell-free shape is deliberate. | `--test-isolation=none` |
| `SIGKILL` escalation | Empirically unnecessary — the todo measured both orphans dying on plain `SIGTERM`; the signal was never *delivered*, not ignored. | nothing |
| Raising `NODE_TEST_TIMEOUT_MS` (`src/prohibition-enforcement.cts:449`) | Moves the cliff, does not remove the leak — a longer bound just means a later orphan. Same anti-pattern #869 called out for CI timeouts. | `--test-isolation=none` |

### Caveat to verify during the fix (from the todo, restated because it is the one real risk)

With isolation `none`, the target file is **imported into the runner process** and shares globals
with it. Confirm the `GSD_PROHIB_SUBJECT` convention (#1279) and the `childEnv()`
`NODE_TEST_CONTEXT`/`NODE_OPTIONS` stripping still behave — that stripping exists precisely to stop
an ambient runner context corrupting the verdict, and this change moves the boundary it guards.

---

## Q3 — Making an invariant's DELETION fail CI

**Recommendation: three layers, all from packages already in `devDependencies`. No new tool.**

Distinguish two failures that the graphify case conflates:

- **Violation with blind tests** — `applyBudget` stops honouring the seed floor and
  `tests/graphify-query.test.cjs:560`/`:587` still pass, because `arbGraph` (`:513-538`) produced
  **≥2 seeds in 0 of 200 runs** at the pinned `numRuns: 200, seed: 42`.
- **Deletion** — someone removes lines `:560`/`:587` and nothing anywhere notices.

They need different mechanisms. Build all three.

### Layer 1 — the deletion tripwire (this is the direct answer to the question)

A plain `node:test` **invariant-title lock**: a registry of the invariant test titles that must
exist, plus a test that parses `tests/graphify-query.test.cjs` with **`espree`** (already a
devDependency, `^10.4.0`) and asserts each registered title is still present as a `test(...)` /
`describe(...)` call. Deleting an assertion without deleting its registry entry reds CI; deleting
the registry entry is a loud, reviewable diff that cannot be mistaken for cleanup.

- **Precedent and rationale already written down:** `tests/portability-vocab-drift.test.cjs`. ADR-1703
  records *why* this is a plain `node:test` and not an ESLint `RuleTester` case — *"`RuleTester`…
  only feeds code strings to a rule and cannot read files or enumerate exports."* Same reason here.
- **Alternative primitive, same repo, zero new code:** `scripts/lib/allowlist-ratchet.cjs` already
  implements exactly the wanted semantics — *"A REMOVED … file with a stale allowlist entry **also
  fails**, so the baseline only ever shrinks"* (`scripts/lint-regression-test-names.cjs:22-26`).
  Pick whichever fits; do not hand-roll a third.

⚠ **`scripts/lint-removed-but-needed.cjs` does not cover this.** It keys on deleted **files**
(`git diff --name-status`, status `D`) and greps survivors for the basename. A deleted *assertion
inside a surviving file* is invisible to it. Say so explicitly, or a phase will assume it is
already handled.

### Layer 2 — cure the blindness

- Strengthen `arbGraph` so it reliably generates **≥2 differentiated-quality seeds** — `fast-check`
  `^4.8.0` is already a devDependency. The existing arbitrary only produces a second seed if
  `fc.string({minLength:1,maxLength:6})` happens to emit the substring `auth`.
- Add the counterexample RED test from
  `.planning/runbooks/porting-local-patches-assets/graphify/4.3b-seedfloor-counterexample.cjs`
  (the budget-120-survives / budget-150-evicts case). It is already written and is a ready template.
- Do **not** quietly edit `:560`/`:587`. If they must change, say why in the same commit — they are
  the written record of the contract.

### Layer 3 — the semantic backstop, and the two-part wiring it actually needs

Add `graphify` to `COVERED` in `scripts/mutation-matrix.cjs` with a CI-measured `minScore`.
`@stryker-mutator/core ^9.6.1` is already in the stack; `graphify.cjs` is **not** in
`stryker.config.mjs`'s `UNMUTATED` exclusion list, so it is already mutable — it simply has no
shard. Mutation testing kills the blindness class directly: a fixture that cannot reach a branch
leaves survivors and drops the score.

**Verified wiring detail — the `COVERED` entry alone is dead.** Two gates sit in series, and only
one of them handles test-file changes:

1. `scripts/mutation-matrix.cjs:206-216` adds **every `COVERED` module's `tests[]` entries** to
   `GLOBAL_TRIGGERS`, and `computeMatrix` (`:271-277`) returns **all** module names when any
   changed file is a global trigger. So *within the script*, a changed test file does select the
   module. Good.
2. But `.github/workflows/mutation.yml:15-25` gates the entire workflow on an `on.paths`
   allow-list: `src/**/*.cts`, `gsd-core/bin/lib/**/*.cjs`, `tests/**/*.property.test.cjs`,
   `tests/**/*.unit.test.cjs`, three named test files, `stryker.config.mjs`,
   `scripts/mutation-matrix.cjs`. **`tests/graphify-query.test.cjs` matches none of them** — it is
   neither `.property.` nor `.unit.`, and it is not one of the three. A PR touching only that file
   **never starts the workflow**, so step 1 never runs.

➡ **Adding `graphify` to `COVERED` therefore requires adding `tests/graphify-query.test.cjs` to
`mutation.yml`'s `paths:` list in the same change**, or the entry is inert for test-only edits.

**And even correctly wired, mutation score is a threshold, not an identity lock.** Floors are set
at "measured minus 1–2 points for run-to-run variance" (`scripts/mutation-matrix.cjs:107-122`), so
deleting one property assertion among several can drop the score by less than the margin and pass.
That is the durable reason Layer 1 stays: Stryker answers *"are these tests strong enough?"*,
Layer 1 answers *"does this named invariant still exist?"* — different questions.

Honour the calibration rule already recorded at `scripts/mutation-matrix.cjs:116-122`: **floors
must come from a CI run.** Local runs count timeouts as kills and inflate scores (measured:
`prompt-budget` 99.6% local vs 68.3% CI). Do not set `minScore` from a local number.

### What NOT to add (Q3)

| Avoid | Why | Use instead |
|---|---|---|
| A new coverage tool | `c8 ^11.0.0` is already present, and line coverage **cannot see a deleted assertion** — deleting one test lowers no line count if any other test covers the same lines. Wrong instrument. | espree title-lock + Stryker |
| `jest` / `vitest` snapshot of test names | Adds a second test framework to a `node:test` repo for one registry file. `--experimental-test-snapshots` in `node:test` would be closer, but a plain array literal is simpler and diffs better. | a `const INVARIANTS = [...]` array + espree |
| A bespoke YAML/JSON invariant manifest parser | `js-yaml ^4.3.1` exists, but a new manifest format is a new schema to drift. `scripts/lib/allowlist-ratchet.cjs` already owns this shape in this repo. | `allowlist-ratchet.cjs` or a JS array |
| Relying on `scripts/lint-fix-has-regression-test.cjs` | It asserts a fix commit *touched* some `tests/*.test.cjs` — a commit that deletes an assertion and adds an unrelated one passes it cleanly. | Layer 1 |
| Relying on `scripts/lint-removed-but-needed.cjs` | Keys on deleted files, not deleted assertions (above). | Layer 1 |
| Adding `graphify` to `COVERED` **only** | Inert for test-only changes until `mutation.yml`'s `paths:` allow-list also lists the test file (above). | change both, in one commit |

---

## Installation

```bash
# Q1(b) only. Q1(a), Q2 and Q3 require no installation.
npm install -D web-tree-sitter@0.26.13 tree-sitter-bash@0.25.1
```

That is the **entire** dependency delta for this milestone. Both are MIT; `web-tree-sitter` has
zero dependencies; both land in `devDependencies` and are **not** in `package.json`'s `files[]`
surface, so neither reaches an `@opengsd/gsd-core` consumer's `node_modules`. Contributor/CI
install weight is ~1.6 MB of WASM.

Everything else needed is already declared:

| Already present | Version | Used for |
|---|---|---|
| `espree` | `^10.4.0` | Q3 Layer 1 — parse the test file for the invariant-title lock |
| `fast-check` | `^4.8.0` | Q3 Layer 2 — strengthen `arbGraph` |
| `@stryker-mutator/core` | `^9.6.1` | Q3 Layer 3 — graphify mutation shard |
| `c8` | `^11.0.0` | unchanged; explicitly *not* the Q3 instrument |
| `node:test` (stdlib) | Node >=24 | dual-shell harness, all new tests |
| `child_process` (stdlib) | Node >=24 | Q2 — nothing else needed |

## Version compatibility

| Package | Compatible with | Notes |
|---|---|---|
| `web-tree-sitter@0.26.13` | no `engines` declared; verified working on the Node in this tree | `type: module`, but ships an `exports.require` condition (`./web-tree-sitter.cjs`) — a `.cjs` lint script can `require()` it. Verified here. |
| `tree-sitter-bash@0.25.1` | grammar artifact only | Consume **`node_modules/tree-sitter-bash/tree-sitter-bash.wasm`** by path. Never `require()` the package — that path is the native binding. Its `node-addon-api`/`node-gyp-build` deps never execute under `npm ci --ignore-scripts`. |
| tree-sitter grammar ABI | `web-tree-sitter` and `tree-sitter-bash` must stay ABI-compatible | Pin both exactly and bump together. A grammar built for a newer ABI fails at `Language.load()`, loudly — not silently, so the failure mode is acceptable. |
| `tree-sitter-bash` grammar | bash | **Deliberately** no zsh grammar and none needed — the zsh knowledge is in the rules (see the reframing above). |
| `--test-isolation=none` | Node **≥ v23.6.0** (renamed from `--experimental-test-isolation`) | Well below the `engines.node >=24.0.0` floor — no gate needed. |
| `sh-syntax@0.6.0` (rejected, recorded for completeness) | pins `mvdan.cc/sh/v3 v3.13.1`; `LangZsh` requires ≥ v3.13.0 | The only Node-reachable **zsh 5.9** parser. Revisit only if a future need is dialect *validation* rather than rule-writing. |

## Stack patterns by variant

**If the milestone must ship a portability *ratchet* alongside the fix (the todo's stated
in-scope plan):**
- Take `web-tree-sitter` + `tree-sitter-bash`. The ratchet is the deliverable, and a regex ratchet
  is what ADR-1703 forbids.
- Precedent for shipping a ratchet inside a fix PR: the #2351 PR shipped
  `scripts/lint-portable-timeout.cjs` in the same PR.

**If the milestone ships only the 11-site fix and defers the ratchet:**
- Take **zero** new dependencies. Do the dual-shell harness change
  (`tests/unreachable-shell-guard.test.cjs:144-149`, absolute interpreter paths, plus a macOS
  lane) and nothing else. The harness alone is what makes all six mechanisms visible; without it,
  no lint choice matters.
- Land the CST lint in a follow-up phase with its own ADR amending ADR-3409.

**If `CONTRIBUTING.md:195` "one concern per PR" forces a split (it does):**
- The macOS CI lane is a *workflow* change and can ride the fix PR.
- The CST lint is a new gate — a separate PR, cleanly separable, and it is the piece that needs
  the ADR amendment.

---

## Confidence

| Claim | Confidence | Basis |
|---|---|---|
| ShellCheck has no zsh mode; v0.11.0 is current | HIGH | `shellcheck.1.md` `-s` list; wiki SC1071 / SC1103; CHANGELOG *"Zsh support has been removed"*; releases page |
| `sh-syntax`'s JSON AST is positional-only and cannot express M1–M7 | HIGH | **Measured today** — `Stmt.Cmd` for `echo foo` is `{Pos,End}`; `Word.Lit === ""`; corroborated by its own README (`originalText` required for `print`) |
| `tree-sitter-bash` exposes every M1–M7 shape with named fields and exact text | HIGH | **Measured today** — full s-expression and targeted walk over the real defect shapes; `subscript index:` typed `number` vs `word` |
| Fence corpus parses as real shell (ADR-3409's premise is overstated) | HIGH | Measured over all 1052 shipped fences with four parsers (Probes A–C) |
| `mvdan/sh` v3.13.0+ parses zsh 5.9; `sh-syntax@0.6.0` pins v3.13.1 and exposes `LangZsh` | HIGH | v3.13.0/v3.13.1 release notes; `syntax/parser.go`; `go.mod`; measured `LangVariant.LangZsh === 16` |
| `detached` unavailable on `spawnSync`/`execFileSync`; `signal` async-only; Node documents the grandchild-survives behaviour | HIGH | Node v24 `child_process` docs, option lists and `subprocess.kill()` section |
| `--test-isolation` default `process`, `none` imports into the runner, renamed in v23.6.0 | HIGH | Node v24 CLI + test-runner docs |
| `mutation.yml`'s `paths:` filter excludes `tests/graphify-query.test.cjs`, so a `COVERED` entry alone is inert | HIGH | Read `.github/workflows/mutation.yml:15-25` and `scripts/mutation-matrix.cjs:206-216,271-277` in this tree |
| Homebrew bash precedes `/bin/bash` on GitHub macOS runners | MEDIUM | Not measured on a runner here; the mitigation (absolute paths) is free and correct regardless, so the risk is fully priced out |
| `arbGraph` yields ≥2 seeds in 0/200 runs | HIGH (inherited) | Measured by the port validation on 2026-08-20; recorded in the 4.3b todo. Not re-measured today. |
| `tree-sitter-bash` grammar coverage sufficient for a production lint over all 1052 fences | MEDIUM-HIGH | 1033/1052 error-free measured, and all seven rule shapes confirmed — but the rules themselves have not been written and run against the corpus. A one-day spike closes this. |

## Open questions for the roadmapper

1. **Process substitution vs pipe.** The chosen `< <(find …)` form is bash/zsh-only (measured: it
   is 4 of the `/bin/sh -n` failures). Decide before the `sh` lane goes in: either drop `sh` from
   the shell matrix, or switch to a form that survives it — the two are mutually exclusive and the
   reference doc currently asserts both.
2. **`agents/gsd-verifier.md` has 2 bytes of headroom** (49,150 / 49,152, `tests/agent-size-budget.test.cjs:66`).
   Any fix touching that file must be net-negative. The existing `verification.resolve-file` verb
   swap is 7 bytes shorter and is the only known compliant option.
3. **macOS CI minutes.** GitHub-hosted macOS runners bill at a higher multiplier than Linux. A
   narrow `shell-fences`-only job (not the full suite) keeps the lane a required PR check without
   the cost of a full macOS matrix entry. Recommend scoping the job to the fence tests only.
4. **Whether the M7 `grep -oP` sites** (5 sites, 2 files) ride this milestone or are filed
   separately. Same class, same lint surface, but "one concern per PR" argues for separate.
5. **Whether vendoring the `.wasm` beats a devDependency.** `scripts/lint-vendored-deps.cjs` is
   already in `lint:ci`, so this repo has a vendoring policy. Copying the 1.36 MB grammar into the
   tree removes one dependency but adds a binary blob to git and a manual update path. Recommend
   the devDependency; flagged because that lint will have an opinion.
