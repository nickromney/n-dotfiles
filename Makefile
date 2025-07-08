# Makefile wrapper for install.sh
.PHONY: help install update stow common personal work python typescript rust ai kubernetes vscode all

# Default target
help:
	@echo "Usage: make [profile] [action]"
	@echo ""
	@echo "Profiles:"
	@echo "  common      - Common host setup (any Mac machine)"
	@echo "  personal    - Personal machine setup (common + personal configs)"
	@echo "  work        - Work machine setup (common + work configs)"
	@echo "  python      - Python development setup"
	@echo "  typescript  - TypeScript/Node development setup"
	@echo "  rust        - Rust development setup"
	@echo "  ai          - AI/ML development setup"
	@echo "  kubernetes  - Kubernetes development setup"
	@echo "  vscode      - VSCode development setup"
	@echo ""
	@echo "Actions:"
	@echo "  install     - Install tools (default)"
	@echo "  update      - Update installed tools"
	@echo "  stow        - Run stow for dotfiles"
	@echo ""
	@echo "Examples:"
	@echo "  make common install     - Install common tools for any Mac"
	@echo "  make personal install   - Install personal machine tools"
	@echo "  make work update        - Update work machine tools"
	@echo "  make python install     - Install Python dev tools"

# Base configurations
SHARED_CONFIGS = shared/shell shared/search shared/git shared/neovim shared/file-tools shared/data-tools shared/network
HOST_COMMON = host/common

# Profile definitions
COMMON_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) focus/vscode
PERSONAL_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) host/personal focus/vscode
WORK_CONFIGS = $(SHARED_CONFIGS) $(HOST_COMMON) host/work
PYTHON_CONFIGS = focus/container-base focus/python
TYPESCRIPT_CONFIGS = focus/container-base focus/typescript
RUST_CONFIGS = focus/container-base focus/rust
AI_CONFIGS = focus/container-base focus/ai
KUBERNETES_CONFIGS = focus/container-base focus/kubernetes
VSCODE_CONFIGS = focus/container-base focus/vscode

# Default action
ACTION ?= install

# Profile targets
common:
	@CONFIG_FILES="$(COMMON_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

personal:
	@CONFIG_FILES="$(PERSONAL_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

work:
	@CONFIG_FILES="$(WORK_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

python:
	@CONFIG_FILES="$(PYTHON_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

typescript:
	@CONFIG_FILES="$(TYPESCRIPT_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

rust:
	@CONFIG_FILES="$(RUST_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

ai:
	@CONFIG_FILES="$(AI_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

kubernetes:
	@CONFIG_FILES="$(KUBERNETES_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

vscode:
	@CONFIG_FILES="$(VSCODE_CONFIGS)" ./install.sh $(if $(filter update,$(MAKECMDGOALS)),-u) $(if $(filter stow,$(MAKECMDGOALS)),-s)

# Action targets (these are just placeholders for argument parsing)
install:
	@true

update:
	@true

stow:
	@true

# All target - install everything
all:
	@echo "Installing all configurations..."
	@CONFIG_FILES="$(PERSONAL_CONFIGS) $(PYTHON_CONFIGS) $(TYPESCRIPT_CONFIGS) $(RUST_CONFIGS) $(AI_CONFIGS) $(KUBERNETES_CONFIGS)" ./install.sh -s
