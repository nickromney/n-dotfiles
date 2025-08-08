# Configuration directory
CONFIG_DIR := _configs

# Configuration sets
SHARED_CONFIGS = shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim
HOST_COMMON = host/common
HOST_PERSONAL = host/personal
HOST_WORK = host/work

# Common is an alias for host/common + shared configs
COMMON_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON)

# Configuration combinations
PERSONAL_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) $(HOST_PERSONAL) focus/vscode
WORK_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) $(HOST_WORK) focus/vscode

# Default target
.DEFAULT_GOAL := help

# Help target
help:
	@echo "n-dotfiles Makefile wrapper for install.sh"
	@echo ""
	@echo "Usage: make [target] [install|update|stow]"
	@echo ""
	@echo "Main targets:"
	@echo "  common                   # Install common tools (shared + host/common)"
	@echo "  personal                 # Install personal configuration" 
	@echo "  work                     # Full work Mac setup (runs setup-work-mac.sh)"
	@echo ""
	@echo "Focus targets (install specific tool categories):"
	@echo "  focus-ai                 # Install AI/ML tools (ollama, etc.)"
	@echo "  focus-container-base     # Install Docker and container tools"
	@echo "  focus-kubernetes         # Install Kubernetes tools (kubectl, k9s, helm)"
	@echo "  focus-neovim             # Install Neovim and plugins"
	@echo "  focus-python             # Install Python development tools"
	@echo "  focus-rust               # Install Rust toolchain and utilities"
	@echo "  focus-typescript         # Install Node.js and TypeScript tools"
	@echo "  focus-vscode             # Install VSCode and extensions"
	@echo ""
	@echo "Actions (can be combined with targets):"
	@echo "  install                  # Install packages (default action)"
	@echo "  update                   # Update existing packages"
	@echo "  stow                     # Run stow to create symlinks"
	@echo ""
	@echo "Environment variables:"
	@echo "  VSCODE_CLI               # VSCode binary to use (default: code)"
	@echo ""
	@echo "Examples:"
	@echo "  make common install      # Install common tools"
	@echo "  make personal stow       # Install personal config and create symlinks"
	@echo "  make focus-vscode        # Install VSCode with extensions"
	@echo "  VSCODE_CLI=cursor make focus-vscode  # Install extensions for Cursor"

# Common/Shared configurations
common:
	@CONFIG_FILES="$(COMMON_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

# Personal setup
personal:
	@CONFIG_FILES="$(PERSONAL_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

# Work setup
work:
	@./setup-work-mac.sh

# Focus targets - install specific tool categories
focus-ai:
	@CONFIG_FILES="focus/ai" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-container-base:
	@CONFIG_FILES="focus/container-base" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-kubernetes:
	@CONFIG_FILES="focus/kubernetes" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-neovim:
	@CONFIG_FILES="focus/neovim" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-python:
	@CONFIG_FILES="focus/python" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-rust:
	@CONFIG_FILES="focus/rust" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-typescript:
	@CONFIG_FILES="focus/typescript" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-vscode:
	@CONFIG_FILES="focus/vscode" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

# Action targets (these do nothing by themselves, used with main targets)
install:
	@:

update:
	@:

stow:
	@:

.PHONY: help common personal work focus-ai focus-container-base focus-kubernetes focus-neovim focus-python focus-rust focus-typescript focus-vscode install update stow
