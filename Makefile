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
	@echo "  common      - Install common tools (shared + host/common)"
	@echo "  personal    - Install personal configuration"
	@echo "  work        - Install work configuration"
	@echo ""
	@echo "Focus targets (install specific tool categories):"
	@echo "  focus-vscode    - Install VSCode and extensions"
	@echo "  focus-devops    - Install DevOps tools"
	@echo "  focus-neovim    - Install Neovim and plugins"
	@echo ""
	@echo "Actions (can be combined with targets):"
	@echo "  install     - Install packages (default action)"
	@echo "  update      - Update existing packages"
	@echo "  stow        - Run stow to create symlinks"
	@echo ""
	@echo "Environment variables:"
	@echo "  VSCODE_CLI  - VSCode binary to use (default: code)"
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
focus-vscode:
	@CONFIG_FILES="focus/vscode" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-devops:
	@CONFIG_FILES="focus/devops" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

focus-neovim:
	@CONFIG_FILES="focus/neovim" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

# Action targets (these do nothing by themselves, used with main targets)
install:
	@:

update:
	@:

stow:
	@:

.PHONY: help common personal work focus-vscode focus-devops focus-neovim install update stow
