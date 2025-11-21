# Configuration directory
CONFIG_DIR := _configs

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m

# Configuration sets
SHARED_CONFIGS = shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim
HOST_COMMON = host/common
HOST_PERSONAL = host/personal
HOST_WORK = host/work

# Common is an alias for host/common + shared configs
COMMON_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON)

# Configuration combinations
PERSONAL_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) $(HOST_PERSONAL) host/manual-check focus/containers focus/kubernetes focus/vscode
WORK_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) $(HOST_WORK) host/manual-check focus/containers focus/kubernetes focus/vscode

PROFILES = personal work common
ACTIONS = install update stow configure
DEFAULT_PROFILE := personal
REQUESTED_PROFILE := $(firstword $(filter $(PROFILES),$(MAKECMDGOALS)))
SELECTED_PROFILE := $(strip $(if $(PROFILE),$(PROFILE),$(if $(REQUESTED_PROFILE),$(REQUESTED_PROFILE),$(DEFAULT_PROFILE))))

define profile-configs
$(if $(filter personal,$1),$(PERSONAL_CONFIGS),$(if $(filter work,$1),$(WORK_CONFIGS),$(COMMON_CONFIGS)))
endef

define macos-profile
$(if $(filter work,$1),work,$(if $(filter personal,$1),personal,personal))
endef

PROFILE_CONFIGS := $(call profile-configs,$(SELECTED_PROFILE))
SELECTED_MACOS_PROFILE := $(call macos-profile,$(SELECTED_PROFILE))

# Default target
.DEFAULT_GOAL := help

##@ Help

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)n-dotfiles - Dotfile and Tool Management$(NC)"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$|^##@.*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; /^##@/ {printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5)} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BLUE)Environment variables:$(NC)"
	@echo "  VSCODE_CLI                VSCode binary to use (default: code)"
	@echo ""
	@echo "$(BLUE)Profile Examples:$(NC)"
	@echo "  make personal configure   Apply macOS settings for personal profile"
	@echo "  make work install         Install tools for the work profile"
	@echo "  make work stow            Symlink configs for the work profile"
	@echo "  make work update          Update tools for the work profile"
	@echo ""
	@echo "$(BLUE)Focus Examples:$(NC)"
	@echo "  make focus-vscode         Install VSCode with extensions"
	@echo "  make focus-python update  Update Python development tools"

##@ Main Configurations

.PHONY: personal
personal: ## Personal profile (default) <configure|install|stow|update>
	@if [ -z "$(filter $(ACTIONS),$(MAKECMDGOALS))" ]; then \
		$(MAKE) PROFILE=personal install; \
	fi

.PHONY: common
common: ## Shared profile <configure|install|stow|update>
	@if [ -z "$(filter $(ACTIONS),$(MAKECMDGOALS))" ]; then \
		$(MAKE) PROFILE=common install; \
	fi

.PHONY: personal-setup
personal-setup: ## Full personal Mac setup (packages + macOS settings)
	@./setup-personal-mac.sh

.PHONY: update-all
update-all: ## Update all installed tools (brew, apt, cargo, uv, mas)
	@echo "$(YELLOW)Updating all package managers and tools...$(NC)"
	@echo ""
	@if command -v brew >/dev/null 2>&1; then \
		echo "$(BLUE)Updating Homebrew...$(NC)"; \
		brew update || echo "$(YELLOW)  Warning: brew update failed$(NC)"; \
		brew upgrade || echo "$(YELLOW)  Warning: brew upgrade failed$(NC)"; \
		brew upgrade --cask || echo "$(YELLOW)  Warning: brew cask upgrade failed (some casks may have issues)$(NC)"; \
		brew cleanup || echo "$(YELLOW)  Warning: brew cleanup failed$(NC)"; \
		echo "$(GREEN)✓ Homebrew update completed$(NC)"; \
		echo ""; \
	fi
	@if command -v apt-get >/dev/null 2>&1 && [ "$$(id -u)" -eq 0 ]; then \
		echo "$(BLUE)Updating apt packages...$(NC)"; \
		apt-get update && apt-get upgrade -y && apt-get autoremove -y; \
		echo "$(GREEN)✓ apt updated$(NC)"; \
		echo ""; \
	fi
	@if command -v rustup >/dev/null 2>&1; then \
		echo "$(BLUE)Updating Rust toolchain...$(NC)"; \
		rustup update; \
		echo "$(GREEN)✓ Rust updated$(NC)"; \
		echo ""; \
	fi
	@if command -v uv >/dev/null 2>&1; then \
		echo "$(BLUE)Updating uv itself...$(NC)"; \
		if [ -n "$${GITHUB_TOKEN:-}" ]; then \
			uv self update --token "$$GITHUB_TOKEN"; \
		else \
			uv self update 2>&1 | grep -v "GitHub API rate limit" || echo "$(YELLOW)  Skipped (GitHub rate limit - set GITHUB_TOKEN to avoid)$(NC)"; \
		fi; \
		echo "$(GREEN)✓ uv update attempted$(NC)"; \
		echo ""; \
	fi
	@if command -v mas >/dev/null 2>&1; then \
		echo "$(BLUE)Updating Mac App Store apps...$(NC)"; \
		mas upgrade; \
		echo "$(GREEN)✓ Mac App Store apps updated$(NC)"; \
		echo ""; \
	fi
	@if command -v arkade >/dev/null 2>&1; then \
		echo "$(BLUE)Checking arkade version...$(NC)"; \
		CURRENT=$$(arkade version 2>&1 | grep -o 'Version: [0-9.]*' | cut -d' ' -f2); \
		if [ -n "$${GITHUB_TOKEN:-}" ]; then \
			LATEST=$$(curl -sL -H "Authorization: token $$GITHUB_TOKEN" https://api.github.com/repos/alexellis/arkade/releases/latest | grep '"tag_name"' | cut -d'"' -f4); \
		else \
			LATEST=$$(curl -sL https://api.github.com/repos/alexellis/arkade/releases/latest | grep '"tag_name"' | cut -d'"' -f4); \
		fi; \
		if [ -z "$$LATEST" ]; then \
			echo "$(YELLOW)  Could not check latest version (GitHub rate limit)$(NC)"; \
			echo "$(GREEN)✓ arkade skipped (set GITHUB_TOKEN to check updates)$(NC)"; \
		elif [ "$$CURRENT" != "$$LATEST" ]; then \
			echo "$(YELLOW)Updating arkade from $$CURRENT to $$LATEST...$(NC)"; \
			curl -sLS https://get.arkade.dev | sh; \
			echo "$(GREEN)✓ arkade updated$(NC)"; \
		else \
			echo "$(GREEN)✓ arkade already up-to-date ($$CURRENT)$(NC)"; \
		fi; \
		echo ""; \
	fi
	@echo "$(GREEN)✓ All package managers and tools updated$(NC)"
	@if [ -z "$${GITHUB_TOKEN:-}" ]; then \
		echo ""; \
		echo "$(YELLOW)Tip: Set GITHUB_TOKEN to avoid GitHub API rate limits$(NC)"; \
		echo "     export GITHUB_TOKEN=ghp_your_token_here"; \
	fi

.PHONY: work
work: ## Work profile <configure|install|stow|update>
	@if [ -z "$(filter $(ACTIONS),$(MAKECMDGOALS))" ]; then \
		$(MAKE) PROFILE=work install; \
	fi

.PHONY: work-setup
work-setup: ## Full work Mac setup (runs setup-work-mac.sh)
	@./setup-work-mac.sh

##@ Focus Configurations

.PHONY: focus-ai
focus-ai: ## AI/ML tools <install|stow|update>
	@CONFIG_FILES="focus/ai" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-container-base
focus-container-base: ## Podman and container tools <install|stow|update>
	@CONFIG_FILES="focus/container-base" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-containers
focus-containers: ## Podman container management <install|stow|update>
	@CONFIG_FILES="focus/containers" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-kubernetes
focus-kubernetes: ## Kubernetes tools <install|stow|update>
	@CONFIG_FILES="focus/kubernetes" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-mas
focus-mas: ## Mac App Store apps <install|stow|update>
	@CONFIG_FILES="focus/mas" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-neovim
focus-neovim: ## Neovim and plugins <install|stow|update>
	@CONFIG_FILES="focus/neovim" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-python
focus-python: ## Python development tools <install|stow|update>
	@CONFIG_FILES="focus/python" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-rust
focus-rust: ## Rust toolchain <install|stow|update>
	@CONFIG_FILES="focus/rust" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-typescript
focus-typescript: ## Node.js and TypeScript <install|stow|update>
	@CONFIG_FILES="focus/typescript" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

.PHONY: focus-vscode
focus-vscode: ## VSCode and extensions <install|stow|update>
	@CONFIG_FILES="focus/vscode" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

##@ Actions

.PHONY: install
install: ## Install packages for the selected profile/focus
	@echo "$(BLUE)Installing $(SELECTED_PROFILE) profile...$(NC)"
	@CONFIG_FILES="$(PROFILE_CONFIGS)" ./install.sh

.PHONY: stow
stow: ## Stow dotfiles for the selected profile/focus
	@echo "$(BLUE)Stowing dotfiles for $(SELECTED_PROFILE) profile...$(NC)"
	@CONFIG_FILES="$(PROFILE_CONFIGS)" ./install.sh -s

.PHONY: update
update: ## Update packages for the selected profile/focus
	@echo "$(BLUE)Updating $(SELECTED_PROFILE) profile...$(NC)"
	@CONFIG_FILES="$(PROFILE_CONFIGS)" ./install.sh -u

##@ macOS Configuration

.PHONY: configure
configure: ## Apply macOS settings (dock, defaults) for the selected profile
	@CONFIG_FILE="_macos/$(SELECTED_MACOS_PROFILE).yaml"; \
	if [ ! -f "$$CONFIG_FILE" ]; then \
		echo "$(RED)No macOS config found for $(SELECTED_PROFILE) profile ($$CONFIG_FILE missing)$(NC)"; \
		exit 1; \
	fi; \
	echo "$(BLUE)Applying macOS settings from $$CONFIG_FILE...$(NC)"; \
	./_macos/macos.sh "$(SELECTED_MACOS_PROFILE).yaml"

##@ Quality and Maintenance

.PHONY: clean
clean: ## Clean cached files and build artifacts
	@echo "$(YELLOW)Cleaning cached files...$(NC)"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@find . -name ".DS_Store" -delete 2>/dev/null || true
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

.PHONY: precommit
precommit: ## Run all pre-commit hooks on all files
	@echo "$(YELLOW)Running all pre-commit hooks...$(NC)"
	@echo "$(YELLOW)Note: This runs on ALL files. Git commit hook runs on staged files only.$(NC)"
	@pre-commit run --all-files
	@echo "$(GREEN)✓ All pre-commit checks passed$(NC)"

.PHONY: precommit-check
precommit-check: ## Run pre-commit hooks (always succeeds, for review)
	@echo "$(YELLOW)Running all pre-commit hooks...$(NC)"
	@pre-commit run --all-files || true

.PHONY: precommit-install
precommit-install: ## Install pre-commit hooks
	@echo "$(YELLOW)Installing pre-commit hooks...$(NC)"
	@pre-commit install
	@echo "$(GREEN)✓ Pre-commit hooks installed$(NC)"

.PHONY: test
test: ## Run all tests
	@echo "$(YELLOW)Running all tests...$(NC)"
	@./_test/run_tests.sh
	@echo "$(GREEN)✓ All tests passed$(NC)"

.PHONY: test-install
test-install: ## Run install.sh tests only
	@echo "$(YELLOW)Running install tests...$(NC)"
	@./_test/run_install_tests.sh

.PHONY: test-macos
test-macos: ## Run macOS configuration tests only
	@echo "$(YELLOW)Running macOS tests...$(NC)"
	@./_test/run_macos_tests.sh
