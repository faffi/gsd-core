# gsd-core personal workflow Makefile (local, untracked — .gitignore)
# Drives the next / working / local/<feature> branch model documented in CLAUDE.md.
#
# NOTE: the standing/aggregate branch is named "working", not "local" — a branch
# literally named "local" blocks git from ever creating "local/<slug>" (ref
# namespace collision, "directory file conflict"). See CLAUDE.md.

SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help sync-next feature update-feature list-features \
        rebuild-working push-working sync new-pr verify status clean-merged guard-clean \
        build install install-test

ORIGIN := origin
FORK   := fork

BOLD   := \033[1m
CYAN   := \033[36m
GREEN  := \033[32m
YELLOW := \033[33m
RED    := \033[31m
RESET  := \033[0m

## ── Help ─────────────────────────────────────────────────────────────────

help: ## Show this help
	@echo ""
	@printf "$(BOLD)gsd-core branch workflow$(RESET)  (full model: CLAUDE.md)\n"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-16s$(RESET) %s\n", $$1, $$2}'
	@echo ""

## ── Upstream sync ───────────────────────────────────────────────────────

sync-next: guard-clean ## Fast-forward next from origin/next
	@printf "$(CYAN)→ syncing next from $(ORIGIN)/next$(RESET)\n"
	@git checkout next
	@git fetch $(ORIGIN)
	@git merge --ff-only $(ORIGIN)/next
	@printf "$(GREEN)✓ next @ $$(git rev-parse --short next)$(RESET)\n"

## ── Feature branches (local/<slug>) ────────────────────────────────────

feature: ## New feature branch off next — make feature NAME=slug
	@test -n "$(NAME)" || (printf "$(RED)✗ usage: make feature NAME=slug$(RESET)\n"; exit 1)
	@git checkout -b local/$(NAME) next
	@printf "$(GREEN)✓ local/$(NAME) created off next$(RESET)\n"

update-feature: ## Merge next into a feature branch — make update-feature NAME=slug
	@test -n "$(NAME)" || (printf "$(RED)✗ usage: make update-feature NAME=slug$(RESET)\n"; exit 1)
	@git checkout local/$(NAME)
	@git merge next
	@printf "$(GREEN)✓ local/$(NAME) merged with next$(RESET)\n"

list-features: ## List feature branches with diffstat vs next
	@feats=$$(git branch --list 'local/*' --format='%(refname:short)'); \
	if [ -z "$$feats" ]; then echo "  (none)"; fi; \
	for b in $$feats; do \
		printf "$(CYAN)$$b$(RESET)\n"; \
		git diff --stat next..$$b | tail -1 | sed 's/^/    /'; \
	done

## ── Working branch (standing, disposable) ──────────────────────────────

rebuild-working: guard-clean ## Rebuild working from next + local/* (or FEATURES=a\ b)
	@printf "$(CYAN)→ rebuilding working off next$(RESET)\n"
	@git checkout -B working next
	@feats="$(FEATURES)"; \
	if [ -z "$$feats" ]; then feats=$$(git branch --list 'local/*' --format='%(refname:short)'); fi; \
	if [ -n "$$feats" ]; then \
		echo "  merging: $$feats"; \
		git merge $$feats -m "chore: rebuild working ($$(date +%Y-%m-%d))" || \
			(printf "$(RED)✗ conflict — resolve, then: git commit$(RESET)\n"; exit 1); \
	else \
		echo "  no local/* branches — working == next"; \
	fi
	@printf "$(GREEN)✓ working @ $$(git rev-parse --short working)$(RESET)\n"

push-working: ## Push working to fork (force-with-lease)
	@git push $(FORK) working --force-with-lease
	@printf "$(GREEN)✓ pushed working → $(FORK)$(RESET)\n"

sync: sync-next rebuild-working push-working ## sync-next + rebuild-working + push-working

## ── Contributing ────────────────────────────────────────────────────────

new-pr: ## Start a contribution branch — make new-pr TYPE=fix ISSUE=1234 SLUG=short-desc
	@test -n "$(TYPE)"  || (printf "$(RED)✗ TYPE required (fix/feat/chore/docs/refactor/test/perf/ci/revert)$(RESET)\n"; exit 1)
	@test -n "$(ISSUE)" || (printf "$(RED)✗ ISSUE required — no code before an approved issue$(RESET)\n"; exit 1)
	@test -n "$(SLUG)"  || (printf "$(RED)✗ SLUG required$(RESET)\n"; exit 1)
	@$(MAKE) --no-print-directory sync-next
	@git checkout -b $(TYPE)/$(ISSUE)-$(SLUG) next
	@printf "$(GREEN)✓ $(TYPE)/$(ISSUE)-$(SLUG) created off next$(RESET)\n"
	@echo "  push:  git push $(FORK) $(TYPE)/$(ISSUE)-$(SLUG)"
	@echo "  PR:    gh pr create --base next --repo open-gsd/gsd-core"

## ── Install from this fork ───────────────────────────────────────────────
#
# This fork IS the install source: bin/install.js reads path.join(__dirname, '..')
# and writes to the target config dir. So `skills/gsd-*` and `gsd-core/` edits on
# working/local/* land in ~/.claude on install — the recursive rmSync over
# skills/gsd-* is wipe-then-replace-FROM-HERE, not a destroy.
#
# Do NOT run /gsd-update to update: it shells out to
# `npx -y --package=@opengsd/gsd-core@TAG`, installs upstream's tree, and drops
# every local feature. Use `make sync` then `make install` instead.

build: ## Compile gitignored tsc output into gsd-core/bin/lib (required before install)
	@printf "$(CYAN)→ npm run build$(RESET)\n"
	@npm run build >/dev/null || (printf "$(RED)✗ build failed — rerun without the quiet redirect to see why$(RESET)\n"; exit 1)
	@test -f gsd-core/bin/lib/install-scope.cjs || \
		(printf "$(RED)✗ build produced no install-scope.cjs — bin/install.js will not load$(RESET)\n"; exit 1)
	@printf "$(GREEN)✓ built$(RESET)\n"

install-test: build ## Dry-run the install into /tmp (never touches ~/.claude)
	@printf "$(CYAN)→ installing to /tmp/gsd-fork-test$(RESET)\n"
	@rm -rf /tmp/gsd-fork-test
	@node bin/install.js --claude --global --config-dir /tmp/gsd-fork-test
	@printf "$(GREEN)✓ skills: $$(ls /tmp/gsd-fork-test/skills 2>/dev/null | wc -l | tr -d ' ')  agents: $$(ls /tmp/gsd-fork-test/agents 2>/dev/null | wc -l | tr -d ' ')$(RESET)\n"
	@printf "  try it:  $(CYAN)CLAUDE_CONFIG_DIR=/tmp/gsd-fork-test claude$(RESET)\n"

install: build ## Build, then install this fork globally into ~/.claude
	@printf "$(YELLOW)→ installing $$(git branch --show-current) @ $$(git rev-parse --short HEAD) into $${CLAUDE_CONFIG_DIR:-$$HOME/.claude}$(RESET)\n"
	@if [ "$$(git branch --show-current)" != "working" ]; then \
		printf "$(YELLOW)⚠ not on working — you are installing a single feature branch, not the integrated set$(RESET)\n"; \
	fi
	@git diff --quiet && git diff --cached --quiet || \
		printf "$(YELLOW)⚠ uncommitted changes — they WILL be installed$(RESET)\n"
	@node bin/install.js --claude --global
	@printf "$(GREEN)✓ installed — restart Claude Code to pick up new skills/agents$(RESET)\n"

verify: ## Run the pre-push verification sequence
	@printf "$(CYAN)→ tests (env-scrubbed)$(RESET)\n"
	@env -u GSD_AGENTS_DIR npm test
	@printf "$(CYAN)→ lint:ci$(RESET)\n"
	@npm run lint:ci
	@printf "$(CYAN)→ changeset lint$(RESET)\n"
	@GITHUB_BASE_REF=next node scripts/changeset/lint.cjs
	@printf "$(GREEN)✓ verified — safe to push$(RESET)\n"

## ── Status & hygiene ────────────────────────────────────────────────────

status: ## Branch state at a glance
	@printf "$(BOLD)current:$(RESET)  $$(git branch --show-current)\n"
	@printf "$(BOLD)next:$(RESET)     $$(git rev-parse --short next) (origin/next: $$(git rev-parse --short $(ORIGIN)/next 2>/dev/null || echo '?'))\n"
	@if git show-ref --verify --quiet refs/heads/working; then \
		printf "$(BOLD)working:$(RESET)  $$(git rev-parse --short working), $$(git rev-list --count next..working) ahead of next\n"; \
	fi
	@printf "$(BOLD)features:$(RESET)\n"
	@$(MAKE) --no-print-directory list-features

clean-merged: ## Delete local/* feature branches already merged into next
	@for b in $$(git branch --list 'local/*' --format='%(refname:short)'); do \
		if [ -z "$$(git diff next..$$b)" ]; then \
			printf "$(YELLOW)deleting $$b (no diff vs next)$(RESET)\n"; \
			git branch -D $$b; \
		fi; \
	done

## ── Guards ───────────────────────────────────────────────────────────────

guard-clean:
	@git diff --quiet && git diff --cached --quiet || \
		(printf "$(RED)✗ uncommitted changes — commit or stash first$(RESET)\n"; exit 1)
