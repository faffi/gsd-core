#!/usr/bin/env bash
# Routes stray .planning/{reference,research,runbooks,seeds,todos}/ files that
# were created directly on `working` onto the durable `local/track-planning-history`
# branch, commits them there, and merges back so they're visible on `working` too.
#
# Why this exists: `working` is disposable (CLAUDE.md:40-42) — nothing is ever
# committed there directly, and the pre-commit hook (.git/hooks/pre-commit)
# blocks that. But the hook only fires at commit time. A session can still
# CREATE new planning docs directly on `working` and never commit them there —
# they just sit untracked until someone notices and moves them by hand. That
# happened twice (thread-lifecycle.md, e0e44a1e recovery; gsd-lifecycle-diagram.md
# + gsd-lifecycle-events.md, 2026-08-21). This script is the repeatable version
# of the manual dance both times: switch branch, add+commit, switch back, merge.
#
# Usage:
#   ./route-planning-docs.sh "commit message"
#
# Only touches .planning/{reference,research,runbooks,seeds,todos}/ paths that
# are untracked or modified on `working` right now — never a blanket `git add`,
# so it can't accidentally sweep in unrelated staged changes (see the
# .hook-test.md incident this session, fixed via reset --hard).

set -euo pipefail

MSG="${1:-}"
if [ -z "$MSG" ]; then
  echo "Usage: ./route-planning-docs.sh \"commit message\"" >&2
  exit 1
fi

DURABLE_BRANCH="local/track-planning-history"
PLANNING_GLOB='^\.planning/(reference|research|runbooks|seeds|todos)/'

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "working" ]; then
  echo "✗ Must be run from \`working\` (currently on \`$branch\`)." >&2
  exit 1
fi

# Untracked + modified (not staged elsewhere) paths under the tracked .planning/ subdirs.
# (Portable read loop, not `mapfile` — macOS ships bash 3.2, which lacks it.)
files=()
while IFS= read -r line; do
  [ -n "$line" ] && files+=("$line")
done < <(
  git status --porcelain -- .planning/reference .planning/research .planning/runbooks .planning/seeds .planning/todos \
    | awk '{print substr($0,4)}' \
    | grep -E "$PLANNING_GLOB" || true
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "Nothing to route — no untracked/modified files under .planning/{reference,research,runbooks,seeds,todos}/."
  exit 0
fi

# Refuse if anything else is staged — don't risk dragging in unrelated work.
if ! git diff --cached --quiet; then
  echo "✗ Refusing: there are already staged changes outside this script's control." >&2
  echo "  Commit or unstage them first, then re-run." >&2
  exit 1
fi

echo "Routing ${#files[@]} file(s) to $DURABLE_BRANCH:"
printf '  %s\n' "${files[@]}"

git checkout "$DURABLE_BRANCH"
git add -- "${files[@]}"
git commit -m "$MSG"

git checkout "$branch"
git merge "$DURABLE_BRANCH" -m "merge: pull planning-doc updates into $branch"

echo "✓ Committed on $DURABLE_BRANCH and merged into $branch."
