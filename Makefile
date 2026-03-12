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

# Configuration combinations (shared first for runtime managers like mise)
PERSONAL_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) $(HOST_PERSONAL) focus/containers focus/kubernetes focus/vscode focus/cloud focus/ai focus/typescript focus/productivity
WORK_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) $(HOST_WORK) focus/containers focus/kubernetes focus/vscode focus/productivity
ALL_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) $(HOST_PERSONAL) $(HOST_WORK) focus/containers focus/kubernetes focus/vscode focus/hardware-home host/manual-check focus/productivity

PROFILES = common personal work all
ACTIONS = install install-dry-run install-system install-preferred install-legacy update stow configure
DEFAULT_PROFILE := $(if $(filter update,$(MAKECMDGOALS)),personal,common)
REQUESTED_PROFILE := $(firstword $(filter $(PROFILES),$(MAKECMDGOALS)))
SELECTED_PROFILE := $(strip $(if $(PROFILE),$(PROFILE),$(if $(REQUESTED_PROFILE),$(REQUESTED_PROFILE),$(DEFAULT_PROFILE))))

define profile-configs
$(if $(filter personal,$1),$(PERSONAL_CONFIGS),$(if $(filter work,$1),$(WORK_CONFIGS),$(if $(filter all,$1),$(ALL_CONFIGS),$(COMMON_CONFIGS))))
endef

define macos-profile
$(if $(filter work,$1),work,$(if $(filter personal,$1),personal,personal))
endef

PROFILE_CONFIGS := $(call profile-configs,$(SELECTED_PROFILE))
SELECTED_MACOS_PROFILE := $(call macos-profile,$(SELECTED_PROFILE))
HOST_OS := $(shell uname -s)

BREWFILE_PERSONAL := Brewfile
BREWFILE_WORK := Brewfile.work
BREWFILE_COMMON := Brewfile.common
BREWFILE_ALL := Brewfile.all
BREWFILE_POSIX := Brewfile.posix

define profile-brewfile
$(if $(filter work,$1),$(BREWFILE_WORK),$(if $(filter common,$1),$(BREWFILE_COMMON),$(if $(filter all,$1),$(BREWFILE_ALL),$(BREWFILE_PERSONAL))))
endef

SELECTED_BREWFILE := $(if $(filter Darwin,$(HOST_OS)),$(call profile-brewfile,$(SELECTED_PROFILE)),$(BREWFILE_POSIX))

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
	@echo "  make install             Safe base install (common profile by default)"
	@echo "  make update              Update installed tools (personal profile by default)"
	@echo "  make install personal    Personal profile install"
	@echo "  make install work        Work profile install"
	@echo "  make install all         All profile bundles"
	@echo "  make personal configure   Apply macOS settings for personal profile"
	@echo "  make work install         Config-driven install (arkade preferred -> brew/apt fallback -> mise)"
	@echo "  make work stow            Symlink configs for the work profile"
	@echo "  make work update          Update tools for the work profile"
	@echo ""
	@echo "$(BLUE)Focus Examples:$(NC)"
	@echo "  make vscode install       Install VSCode with extensions"
	@echo "  make kubernetes update    Update Kubernetes tools"
	@echo "  make python stow          Stow Python configurations"

##@ Main Configurations

.PHONY: personal
personal: ## Personal profile <configure|install|stow|update>
	@if [ -z "$(filter $(ACTIONS),$(MAKECMDGOALS))" ]; then \
		$(MAKE) PROFILE=personal install; \
	fi

.PHONY: common
common: ## Shared/safe base profile (default) <configure|install|stow|update>
	@if [ -z "$(filter $(ACTIONS),$(MAKECMDGOALS))" ]; then \
		$(MAKE) PROFILE=common install; \
	fi

.PHONY: all
all: ## All profile bundles <configure|install|stow|update>
	@if [ -z "$(filter $(ACTIONS),$(MAKECMDGOALS))" ]; then \
		$(MAKE) PROFILE=all install; \
	fi

.PHONY: personal-setup
personal-setup: ## Full personal Mac setup (packages + macOS settings)
	@./setup-personal-mac.sh

.PHONY: update-all
update-all: ## Update all installed tools (brew, apt, cargo, uv, mas, mise)
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
	@if command -v mise >/dev/null 2>&1; then \
		echo "$(BLUE)Updating mise runtimes...$(NC)"; \
		mise upgrade || echo "$(YELLOW)  Warning: mise upgrade failed$(NC)"; \
		echo "$(GREEN)✓ mise upgrade attempted$(NC)"; \
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

##@ Package Manager Updates

.PHONY: brew
brew: ## Homebrew package manager <update>
	@if [ -z "$(filter update,$(MAKECMDGOALS))" ]; then \
		echo "$(YELLOW)Usage: make brew update$(NC)"; \
		exit 1; \
	fi

.PHONY: cargo
cargo: ## Cargo/Rust package manager <update>
	@if [ -z "$(filter update,$(MAKECMDGOALS))" ]; then \
		echo "$(YELLOW)Usage: make cargo update$(NC)"; \
		exit 1; \
	fi

.PHONY: uv
uv: ## UV Python package manager <update>
	@if [ -z "$(filter update,$(MAKECMDGOALS))" ]; then \
		echo "$(YELLOW)Usage: make uv update$(NC)"; \
		exit 1; \
	fi

.PHONY: mas
mas: ## Mac App Store package manager <update>
	@if [ -z "$(filter update,$(MAKECMDGOALS))" ]; then \
		echo "$(YELLOW)Usage: make mas update$(NC)"; \
		exit 1; \
	fi

##@ Focus Configurations

# List of available focus areas
FOCUS_AREAS = ai app-store cloud container-base containers hardware-home infrastructure kubernetes neovim productivity python rust typescript vscode

# Dynamic pattern rule for focus areas
.PHONY: $(FOCUS_AREAS)
$(FOCUS_AREAS):
	@CONFIG_FILES="focus/$@" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s) $(if $(filter install-dry-run,$(MAKECMDGOALS)),-d)

# Help text for focus areas
ai: ## AI/ML tools <install|stow|update>
app-store: ## Mac App Store apps <install|stow|update>
cloud: ## Cloud provider CLIs (AWS, Azure) <install|stow|update>
container-base: ## Podman and container tools <install|stow|update>
containers: ## Podman container management <install|stow|update>
hardware-home: ## Home hardware + chargeable apps (optional) <install|stow|update>
infrastructure: ## IaC tools (Terraform, Ansible) <install|stow|update>
kubernetes: ## Kubernetes tools <install|stow|update>
neovim: ## Neovim and plugins <install|stow|update>
productivity: ## Productivity apps <install|stow|update>
python: ## Python development tools <install|stow|update>
rust: ## Rust toolchain <install|stow|update>
typescript: ## Node.js and TypeScript <install|stow|update>
vscode: ## VSCode and extensions <install|stow|update>

##@ Actions

.PHONY: manifests-generate
manifests-generate: ## Generate install manifests for the selected profile
	@OUT_DIR=".generated/manifests/$(SELECTED_PROFILE)"; \
	mkdir -p "$$OUT_DIR"; \
	echo "$(BLUE)Generating install manifests in $$OUT_DIR...$(NC)"; \
	./scripts/generate-install-manifests.sh "$$OUT_DIR" $(PROFILE_CONFIGS); \
	echo "$(GREEN)✓ Install manifests generated$(NC)"

.PHONY: brewfile-generate
brewfile-generate: ## Generate Brewfile variants from _configs
	@echo "$(BLUE)Generating Brewfiles from config bundles...$(NC)"
	@./scripts/generate-brewfile.sh "$(BREWFILE_COMMON)" $(COMMON_CONFIGS)
	@./scripts/generate-brewfile.sh "$(BREWFILE_PERSONAL)" $(PERSONAL_CONFIGS)
	@./scripts/generate-brewfile.sh "$(BREWFILE_WORK)" $(WORK_CONFIGS)
	@./scripts/generate-brewfile.sh "$(BREWFILE_ALL)" $(ALL_CONFIGS)
	@POSIX_CONFIGS="$$(sed -e 's/#.*$$//' -e '/^[[:space:]]*$$/d' _configs/host/personal-posix.list | paste -sd' ' -)"; \
	./scripts/generate-brewfile.sh "$(BREWFILE_POSIX)" $$POSIX_CONFIGS
	@echo "$(GREEN)✓ Brewfiles generated$(NC)"

.PHONY: brewfile-install
brewfile-install: ## Install from the selected profile Brewfile (preferred)
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "$(RED)Homebrew is required for brewfile-install$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(SELECTED_BREWFILE)" ]; then \
		echo "$(YELLOW)$(SELECTED_BREWFILE) not found; generating Brewfiles first...$(NC)"; \
		$(MAKE) brewfile-generate; \
	fi
	@echo "$(BLUE)Installing via brew bundle: $(SELECTED_BREWFILE)$(NC)"
	@brew bundle --file="$(SELECTED_BREWFILE)"

.PHONY: runtime-install
runtime-install: ## Install runtimes declared in local mise.toml (project-level)
	@if [ ! -f "mise.toml" ]; then \
		echo "$(YELLOW)mise.toml not found; skipping runtime installation$(NC)"; \
	elif command -v mise >/dev/null 2>&1; then \
		if [ "$(DRY_RUN)" = "true" ]; then \
			echo "$(BLUE)[DRY RUN] Previewing runtimes via mise...$(NC)"; \
			mise install --dry-run; \
			echo "$(GREEN)[DRY RUN] ✓ mise runtime preview complete (no changes made)$(NC)"; \
		else \
			echo "$(BLUE)Installing runtimes via mise...$(NC)"; \
			mise install; \
			echo "$(GREEN)✓ mise runtimes installed$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)mise not found; skipping runtime installation$(NC)"; \
	fi

.PHONY: install-system
install-system: ## Install system dependencies from config (arkade preferred, then brew/apt fallback via install.sh)
	@echo "$(BLUE)Installing system dependencies from $(SELECTED_PROFILE) profile config...$(NC)"
	@CONFIG_FILES="$(PROFILE_CONFIGS)" ./install.sh

.PHONY: install-preferred
install-preferred: ## Backward-compatible alias for install
	@$(MAKE) PROFILE=$(SELECTED_PROFILE) install

.PHONY: install
install: ## Install selected profile/focus (system deps first, then project runtimes)
ifneq ($(filter $(FOCUS_AREAS),$(MAKECMDGOALS)),)
	@: # No-op if a focus target was specified
else
	@$(MAKE) PROFILE=$(SELECTED_PROFILE) install-system
	@$(MAKE) runtime-install
endif

.PHONY: install-dry-run
install-dry-run: ## Preview install for selected profile (no system changes)
	@$(MAKE) PROFILE=$(SELECTED_PROFILE) DRY_RUN=true install

.PHONY: install-legacy
install-legacy: ## Legacy installer path (install.sh directly)
	@echo "$(YELLOW)install.sh is deprecated as the primary path; prefer 'make install'.$(NC)"
	@CONFIG_FILES="$(PROFILE_CONFIGS)" ./install.sh

.PHONY: stow
stow: ## Stow dotfiles for the selected profile/focus
ifneq ($(filter $(FOCUS_AREAS),$(MAKECMDGOALS)),)
	@: # No-op if a focus target was specified
else
	@echo "$(BLUE)Stowing dotfiles for $(SELECTED_PROFILE) profile...$(NC)"
	@CONFIG_FILES="$(PROFILE_CONFIGS)" ./install.sh -s
endif

.PHONY: update
update: ## Update packages for the selected profile/focus/package-manager (only one package manager per invocation)
ifneq ($(filter $(FOCUS_AREAS),$(MAKECMDGOALS)),)
	@: # No-op if a focus target was specified
else ifneq ($(filter brew,$(MAKECMDGOALS)),)
	@if command -v brew >/dev/null 2>&1; then \
		echo "$(BLUE)Updating Homebrew packages and casks...$(NC)"; \
		brew update || echo "$(YELLOW)  Warning: brew update failed$(NC)"; \
		brew upgrade || echo "$(YELLOW)  Warning: brew upgrade failed$(NC)"; \
		brew upgrade --cask || echo "$(YELLOW)  Warning: brew upgrade --cask failed$(NC)"; \
		brew cleanup || echo "$(YELLOW)  Warning: brew cleanup failed$(NC)"; \
		echo "$(GREEN)✓ Homebrew updated$(NC)"; \
	else \
		echo "$(RED)Homebrew is not installed$(NC)"; \
		exit 1; \
	fi
else ifneq ($(filter cargo,$(MAKECMDGOALS)),)
	@if command -v rustup >/dev/null 2>&1; then \
		echo "$(BLUE)Updating Rust toolchain...$(NC)"; \
		rustup update; \
		echo "$(GREEN)✓ Rust toolchain updated$(NC)"; \
		echo ""; \
	else \
		echo "$(RED)Rust/cargo is not installed$(NC)"; \
		exit 1; \
	fi
	@if command -v cargo-install-update >/dev/null 2>&1; then \
		echo "$(BLUE)Updating cargo-installed binaries...$(NC)"; \
		cargo install-update -a; \
		echo "$(GREEN)✓ Cargo binaries updated$(NC)"; \
	else \
		echo "$(YELLOW)Install cargo-update for binary updates: cargo install cargo-update$(NC)"; \
	fi
else ifneq ($(filter uv,$(MAKECMDGOALS)),)
	@if command -v uv >/dev/null 2>&1; then \
		echo "$(BLUE)Updating uv...$(NC)"; \
		uv self update; \
		echo "$(GREEN)✓ uv updated$(NC)"; \
		echo "$(YELLOW)Note: Use './install.sh -u' to update individual uv tools$(NC)"; \
	else \
		echo "$(RED)uv is not installed$(NC)"; \
		exit 1; \
	fi
else ifneq ($(filter mas,$(MAKECMDGOALS)),)
	@if command -v mas >/dev/null 2>&1; then \
		echo "$(BLUE)Updating Mac App Store apps...$(NC)"; \
		mas upgrade; \
		echo "$(GREEN)✓ Mac App Store apps updated$(NC)"; \
	else \
		echo "$(RED)mas is not installed$(NC)"; \
		exit 1; \
	fi
else
	@echo "$(BLUE)Updating $(SELECTED_PROFILE) profile...$(NC)"
	@CONFIG_FILES="$(PROFILE_CONFIGS)" ./install.sh -u
endif

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

.PHONY: audit-installed
audit-installed: ## Audit installed brew/npm packages vs YAML-managed entries
	@./scripts/audit-installed.sh

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
