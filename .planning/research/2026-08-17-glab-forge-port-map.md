# GSD `gh` → `glab` port map (verified)

> **STATUS 2026-08-17: IMPLEMENTED as a local patch.** All 14 call sites edited in
> `~/.claude` against installed 1.10.0, registered as item 14 in
> `runbooks/gsd-update-runbook.md` and appended to
> `scripts/gsd-local-patches-1.10.0.diff`. Pristine baselines seeded in
> `gsd-pristine/`. Reapply verified: `patch -p1` from pristine reproduces all four
> files byte-identically.
>
> **Upstream is closed to this.** open-gsd/gsd-core#2138 asked for glab support;
> maintainer reply 2026-07-12: *"gitlab will not be added, it is not supported by
> us. we use GitHub exclusively."* Permanent local patch — do not re-propose.

**Verified 2026-08-17 against two independent sources:**
- context7 `/gitlab_gitlab-org/cli` (High reputation, 1563 snippets) — docs pages *and* Go source from `main`
- installed binary `glab 1.107.0 (85b59ceb)` — `--help` output

Every flag below was confirmed in both unless a drift note says otherwise.

## Call-site inventory

`gh` appears in 5 markdown files + 1 code file across `gsd-core/`. Skills, agents and hooks
carry none (thin wrappers).

### `gsd-core/workflows/ship.md` — 3 sites

| Line | Current | glab equivalent |
|---|---|---|
| :90 | `which gh && gh auth status` | `glab auth status` (`-a/--all`, `--hostname HOST`, `-t/--show-token`) |
| :338 | `gh pr create --title --body-file F --base B` | `glab mr create -t "TITLE" -d "$(cat F)" -b "$BASE_BRANCH" -s "$CURRENT_BRANCH" -y` |
| :435 | `gh pr edit N --add-reviewer U` | `glab mr update N --reviewer +U` |

**Traps at :338**
- There is **no `--body-file` / `--description-file`**. `-d/--description` takes a string only.
  `-d -` opens an editor — fatal in a non-interactive workflow. Read the temp file into the flag.
- `--template` is **mutually exclusive** with `--description` (enforced by
  `MarkFlagsMutuallyExclusive` in `mr_create.go`). Don't emit both.
- Draft flag is `--draft` (alias `--wip`).
- Squash-on-create is **`--squash-before-merge`**, NOT `--squash`. `--squash`/`-s` exists only on
  `glab mr merge`, where `-s` means squash — while on `mr create` `-s` means `--source-branch`.
  Same letter, opposite meaning, adjacent commands.

**Trap at :435**
- `gh pr edit --add-reviewer` is **additive**. `glab mr update --reviewer` **replaces** the reviewer
  list by default; prefix `+` to add, `!` or `-` to remove. A literal port silently drops existing
  reviewers. Same semantics apply to `-a/--assignee`.

**Reporting "PR #{number} created: {url}"**
- `glab mr view -F json --jq '.iid, .web_url'`, or rely on non-TTY `glab mr view`, which prints
  tab-separated `number:<iid>` and `url:<web_url>` (`rawMRPreview` in `mr_view.go`).

### `gsd-core/workflows/pr-branch.md` — 3 sites

| Line | Current | glab equivalent |
|---|---|---|
| :147 | prose: null `remote_slug` ⇒ skip `gh pr create` | this is today's GitLab path — a silent skip |
| :187, :301 | `gh pr create --base T --head H` | `glab mr create -b T -s H -y` |

**Trap:** glab's `-H/--head` selects **another head repository** (`OWNER/REPO`, project ID, or URL) —
it is *not* `gh`'s `--head <branch>`. The branch flag is `-s/--source-branch`. A literal port of
`--head` produces a wrong-repo MR or an error, not a wrong-branch MR.

### `gsd-core/workflows/inbox.md` — 9 sites

| Line | Current | glab equivalent |
|---|---|---|
| :33 | `which gh && gh auth status` | `glab auth status` |
| :40 | `gh repo view --json nameWithOwner -q '.nameWithOwner'` | `glab repo view -F json --jq '.path_with_namespace'` |
| :57 | `gh issue list --state open --json …` | `glab issue list -O json` |
| :146 | `gh pr list --state open --json …` | `glab mr list -F json` |
| :161 | `gh pr view N --json body -q '.body'` | `glab mr view N -F json --jq '.description'` |
| :310 | `gh issue edit N --add-label L` | `glab issue update N -l L` |
| :314 | `gh pr edit N --add-label L` | `glab mr update N -l L` |
| :327 | `gh issue close N --comment "…"` | **two calls:** `glab issue note N -m "…"` then `glab issue close N` |
| :332 | `gh pr close N --comment "…"` | **two calls:** `glab mr note create N -m "…"` then `glab mr close N` |

**JSON field mapping** (glab `-F json` returns the raw GitLab REST object, so these are API names):

| `gh --json` field | GitLab field |
|---|---|
| `number` | `iid` |
| `body` | `description` |
| `headRefName` | `source_branch` |
| `baseRefName` | `target_branch` |
| `isDraft` | `draft` |
| `author.login` | `author.username` |
| `labels` | `labels` (array of strings, not objects) |
| `createdAt` / `updatedAt` | `created_at` / `updated_at` |
| `reviewDecision` | **no equivalent** — use `glab mr approvers <id> -F json` |
| `statusCheckRollup` | **no equivalent** — use `head_pipeline.status`, or `glab ci status -b <branch> -F json`, or `glab ci list -r <ref> -F json` |

**Trap: `-F` means three different things.**
- `glab mr list` / `mr view` / `repo view` / `issue view` / `ci list` / `ci status`: `-F` = `--output` (`text`\|`json`)
- `glab issue list`: `-O` = `--output` (`text`\|`json`), and `-F` = `--output-format` (`details`\|`ids`\|`urls`)
- `glab api`: `-F` = `--field` (typed POST parameter)

So `glab issue list -F json` does **not** produce JSON — it errors or returns `details`. Issue list is
the one command that uses `-O`.

**Drift note — `glab mr note`:** context7 (`main`) documents `glab mr note -m "msg" <id>`. Installed
1.107.0 has restructured it into subcommands (`create`, `delete`, `list`, `reopen`, `resolve`,
`update`, all marked EXPERIMENTAL); top-level `mr note` exposes only `-h` and `-R`. Use
`glab mr note create <id> -m "msg"`. `glab issue note -m` is unchanged and non-experimental — the two
paths are asymmetric.

### `gsd-core/references/checkpoints.md` — 1 site

`:414` external-CLI table has only a GitHub row. Add:

    | GitLab | `glab` | `mr create`, `ci status`, `api` | `glab auth login` |

### `gsd-core/workflows/forensics.md` — NOT a port target

`:259` `gh label list --repo open-gsd/gsd-core` and `:265` `gh issue create --repo open-gsd/gsd-core`
both hard-target GSD's own upstream repo for bug reports. That repo is on GitHub regardless of the
user's forge. Leave as-is.

## Scope decision (2026-08-17): markdown-only

The operator does not use companion sub-repos, so **no code change is in scope**.

`grep remote_slug` across `gsd-core/` has exactly one consumer: `pr-branch.md:187`
`gh pr create --repo "$REMOTE_SLUG"`, the companion-PR-for-a-sub-repo path fed by
`gsd_run query pr-subrepo` (`pr-branch.md:129` → `cmdPrSubrepo` in `src/commands.cts`,
built to `gsd-core/bin/lib/commands.cjs:1192`). Nothing else reads it:

- `ship.md` — no `remote_slug`, no `pr-subrepo` reference at all; its `gh pr create` is raw bash
- `inbox.md` — all 9 sites are plain bash `gh` calls
- `pr-branch.md:301` — display text inside a "Next steps" echo block, not an executed command

### In scope

| File | Sites |
|---|---|
| `gsd-core/workflows/ship.md` | :90, :338, :435 |
| `gsd-core/workflows/inbox.md` | :33, :40, :57, :146, :161, :310, :314, :327, :332 |
| `gsd-core/workflows/pr-branch.md` | :301 only (make the printed hint forge-aware) |
| `gsd-core/references/checkpoints.md` | :414 (add the GitLab row) |

### Deferred (not blocking)

`src/commands.cts` host-aware `remote_slug` — needed only if companion sub-repo MRs are
ever wanted. The regex is genuinely GitHub-only and does yield `null` for any GitLab
remote, so `pr-branch.md:187` silently skips; that is correct-but-unhelpful behaviour, not
a defect blocking this port. Note the edit belongs in `src/commands.cts` (TypeScript), never
in `gsd-core/bin/lib/commands.cjs` — that path is gitignored `tsc` output.

### Out of scope

`gsd-core/workflows/forensics.md:259,:265` — both hard-target `open-gsd/gsd-core` for
upstream bug reports. GitHub regardless of the user's forge.

## Durability

Every in-scope file lives under `gsd-core/`, which `bin/install.js` **wipe-and-replaces** on
every install and `/gsd-update`. A markdown-only port therefore has no code component that
could survive on its own — it must either land upstream (preferred) or be registered as a
local patch alongside `scripts/gsd-local-patches-1.10.0.diff` and the `gsd-local-patches/`
tree. An unregistered edit will be deleted without warning by the next update, which is the
most likely fate of the earlier glab amendment.

Development flow for the fork (`~/Documents/git/personal/gsd-core`, branch `next`):

    npm run build                                              # lib/ is gitignored tsc output
    node bin/install.js --claude --global -c /tmp/gsd-fork-test  # scratch, not ~/.claude
    CLAUDE_CONFIG_DIR=/tmp/gsd-fork-test claude

## Full verified flag reference (glab 1.107.0)

- `glab mr create`: `-t/--title`, `-d/--description`, `-s/--source-branch`, `-b/--target-branch`,
  `--draft`/`--wip`, `-l/--label`, `-a/--assignee`, `--reviewer`, `--remove-source-branch`,
  `--squash-before-merge`, `--auto-merge`, `-f/--fill`, `--fill-commit-body`, `-y/--yes`,
  `--template`, `-i/--related-issue`, `--copy-issue-labels`, `--create-source-branch`, `--push`,
  `--no-editor`, `-H/--head`, `-R/--repo`, `-w/--web`, `--signoff`, `--allow-collaboration`,
  `-m/--milestone`, `--recover`
- `glab mr update`: `-t/--title`, `-d/--description`, `-l/--label`, `-u/--unlabel`, `-a/--assignee`,
  `--unassign`, `--reviewer`, `--draft`/`--wip`, `-r/--ready`, `--target-branch`,
  `--squash-before-merge`, `--remove-source-branch`, `--lock-discussion`, `--unlock-discussion`,
  `-m/--milestone`, `-f/--fill`
- `glab mr merge`: `-s/--squash`, `--squash-message`, `-d/--remove-source-branch`, `-r/--rebase`,
  `-m/--message`, `--sha`, `--auto-merge`, `-y/--yes`
- `glab mr approve`: `-s/--sha`, `-R/--repo` only
- `glab mr approvers [<id>|<branch>]`: `-F/--output`, `--jq`
- `glab mr view`: `-F/--output`, `--jq`, `-c/--comments`, `--resolved`, `--unresolved`,
  `-s/--system-logs`, `-w/--web`, `-p/--page`, `-P/--per-page`
- `glab issue update`: `-l/--label`, `-u/--unlabel`, `-t/--title`, `-d/--description`,
  `-a/--assignee`, `--unassign`, `-m/--milestone`, `-c/--confidential`, `-p/--public`,
  `-w/--weight`, `--due-date`, `--lock-discussion`, `--unlock-discussion`
- `glab issue close`: `-R/--repo` only — **no `--comment`**
- `glab issue note`: `-m/--message`
- `glab auth status`: `-a/--all`, `--hostname`, `-t/--show-token`
- `glab ci status`: `-b/--branch`, `-l/--live`, `-c/--compact`, `-F/--output`, `--jq`
  (JSON is incompatible with `--live` and `--compact`)
- `glab ci list`: `-r/--ref`, `-s/--status`, `--sha`, `--scope`, `--source`, `-n/--name`,
  `-o/--order`, `--sort`, `-u/--username`, `-a/--updated-after`, `-b/--updated-before`,
  `-y/--yaml-errors`, `-F/--output`, `--jq`, `-p/--page`, `-P/--per-page`
