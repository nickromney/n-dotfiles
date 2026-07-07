# n-dotfiles — three declarative layers:
#   brew bundle   (Brewfile: casks, fonts, mas apps, mac formulae)
#   stow          (stow.sh: symlink dotfiles into $HOME)
#   mise install  (mise/.config/mise/config.toml: CLI tools + runtimes)

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m

BREW_WITH_POLICY := ./scripts/brew-with-policy.sh
BREW_UPDATE := ./scripts/brew-update.sh

HOST_OS := $(shell uname -s)
BREWFILE := $(if $(filter Darwin,$(HOST_OS)),Brewfile,Brewfile.posix)

# macOS settings profile for `make configure` (personal or work)
MACOS_PROFILE ?= personal

# Default target
.DEFAULT_GOAL := help

##@ Help

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)n-dotfiles - Dotfile and Tool Management$(NC)"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$|^##@.*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; /^##@/ {printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5)} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Typical flows:$(NC)"
	@echo "  ./bootstrap.sh            Fresh Mac: Homebrew + Brewfile + stow + mise"
	@echo "  make install              Re-apply Brewfile + stow + mise"
	@echo "  make stow                 Symlink dotfiles only (all a work machine needs)"
	@echo "  make update               Update brew, mise, and mas-managed tools"
	@echo "  make configure            Apply macOS settings (MACOS_PROFILE=personal)"

##@ Install

.PHONY: install
install: brewfile-install stow mise-install ## Apply Brewfile + stow + mise (idempotent)

.PHONY: brewfile-install
brewfile-install: ## Install packages from the Brewfile (Brewfile.posix on Linux)
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "$(RED)Homebrew is required; run ./bootstrap.sh first$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Installing via brew bundle: $(BREWFILE)$(NC)"
	@$(BREW_WITH_POLICY) bundle --file="$(BREWFILE)"

.PHONY: stow
stow: ## Symlink dotfiles into the home directory
	@./stow.sh

.PHONY: mise-install
mise-install: ## Install CLI tools and runtimes declared in mise config
	@if command -v mise >/dev/null 2>&1; then \
		echo "$(BLUE)Installing tools and runtimes via mise...$(NC)"; \
		mise install; \
		echo "$(GREEN)✓ mise tools installed$(NC)"; \
	else \
		echo "$(RED)mise not found; run ./bootstrap.sh or 'brew install mise'$(NC)"; \
		exit 1; \
	fi

.PHONY: personal-setup
personal-setup: ## Full personal Mac setup (bootstrap + macOS settings + SSH)
	@./setup-personal-mac.sh

##@ Update

.PHONY: update
update: ## Update brew packages, mise tools, and Mac App Store apps
	@$(BREW_UPDATE) update-all
	@if command -v mise >/dev/null 2>&1; then \
		echo "$(BLUE)Updating mise tools and runtimes...$(NC)"; \
		mise upgrade || echo "$(YELLOW)  Warning: mise upgrade failed$(NC)"; \
		echo "$(GREEN)✓ mise upgrade attempted$(NC)"; \
		echo ""; \
	fi
	@if command -v mas >/dev/null 2>&1; then \
		echo "$(BLUE)Updating Mac App Store apps...$(NC)"; \
		mas upgrade; \
		echo "$(GREEN)✓ Mac App Store apps updated$(NC)"; \
		echo ""; \
	fi
	@if command -v rustup >/dev/null 2>&1; then \
		echo "$(BLUE)Updating Rust toolchain...$(NC)"; \
		rustup update; \
		echo "$(GREEN)✓ Rust updated$(NC)"; \
		echo ""; \
	fi
	@echo "$(GREEN)✓ All package managers and tools updated$(NC)"

##@ macOS Configuration

.PHONY: configure
configure: ## Apply macOS settings (dock, defaults); MACOS_PROFILE=personal|work
	@CONFIG_FILE="_macos/$(MACOS_PROFILE).yaml"; \
	if [ ! -f "$$CONFIG_FILE" ]; then \
		echo "$(RED)No macOS config found at $$CONFIG_FILE$(NC)"; \
		exit 1; \
	fi; \
	echo "$(BLUE)Applying macOS settings from $$CONFIG_FILE...$(NC)"; \
	./_macos/macos.sh "$(MACOS_PROFILE).yaml"

##@ Quality and Maintenance

.PHONY: clean
clean: ## Clean cached files and build artifacts
	@echo "$(YELLOW)Cleaning cached files...$(NC)"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@rm -rf "$${XDG_CACHE_HOME:-$$HOME/.cache}/zsh-init" && echo "  Cleared zsh init cache" || true
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: fmt
fmt: ## Format all code (markdown, shell scripts)
	@echo "$(YELLOW)Formatting markdown files...$(NC)"
	@find . -name "*.md" -not -path "./_test/*" -not -path "./.git/*" -exec markdownlint --fix {} + 2>/dev/null || echo "  markdownlint not available"
	@echo "$(GREEN)✓ Formatting complete$(NC)"

.PHONY: lint
lint: ## Run linters (shellcheck, markdownlint)
	@echo "$(YELLOW)Running shellcheck...$(NC)"
	@./_test/shellcheck.sh
	@echo "$(YELLOW)Running markdownlint...$(NC)"
	@find . -name "*.md" -not -path "./_test/*" -not -path "./.git/*" -exec markdownlint {} + 2>/dev/null || echo "  markdownlint not available"
	@echo "$(GREEN)✓ Linting complete$(NC)"

.PHONY: hooks
hooks: ## Run the lefthook pre-commit checks on all files
	@echo "$(YELLOW)Running lefthook pre-commit checks on all files...$(NC)"
	@echo "$(YELLOW)Note: The git commit hook runs on staged files only.$(NC)"
	@lefthook run pre-commit --all-files
	@echo "$(GREEN)✓ All hook checks passed$(NC)"

.PHONY: hooks-install
hooks-install: ## Install lefthook git hooks into .git/hooks
	@echo "$(YELLOW)Installing lefthook git hooks...$(NC)"
	@lefthook install
	@echo "$(GREEN)✓ lefthook hooks installed$(NC)"

.PHONY: test
test: ## Run all tests
	@echo "$(YELLOW)Running all tests...$(NC)"
	@./_test/run_tests.sh
	@echo "$(GREEN)✓ All tests passed$(NC)"

.PHONY: test-macos
test-macos: ## Run macOS configuration tests only
	@echo "$(YELLOW)Running macOS tests...$(NC)"
	@./_test/run_macos_tests.sh

.PHONY: audit-installed
audit-installed: ## Audit installed packages vs Brewfile and mise config
	@./scripts/audit-installed.sh

.PHONY: audit-local-git
audit-local-git: ## Fast local-only audit for repos under ~/Developer/personal
	@./scripts/audit-local-git-repos.sh --execute

.PHONY: audit
audit: ## Alias for audit-installed
	@./scripts/audit.sh

##@ Linux/Lima Validation

.PHONY: test-lima-up
test-lima-up: ## Start Ubuntu 24.04 Lima VM used for POSIX/non-mac smoke tests
	@./_test/lima/lima-posix.sh up

.PHONY: test-lima-run
test-lima-run: ## Run POSIX/non-mac smoke tests inside the Lima VM
	@./_test/lima/lima-posix.sh run

.PHONY: test-lima
test-lima: ## Start Lima VM (if needed) and run POSIX/non-mac smoke tests
	@./_test/lima/lima-posix.sh test

.PHONY: test-lima-status
test-lima-status: ## Show Lima VM status for the POSIX/non-mac test instance
	@./_test/lima/lima-posix.sh status

.PHONY: test-lima-down
test-lima-down: ## Stop the Lima POSIX/non-mac test VM (preserves state)
	@./_test/lima/lima-posix.sh down

.PHONY: test-lima-destroy
test-lima-destroy: ## Delete the Lima POSIX/non-mac test VM
	@./_test/lima/lima-posix.sh destroy

##@ Tools

.PHONY: browser-tools
browser-tools: ## Build browser-tools binary (requires bun)
	@./scripts/build-browser-tools.sh
