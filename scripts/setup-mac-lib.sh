#!/usr/bin/env bash

COMMON_SETUP_CONFIGS=(
  "shared/shell"
  "shared/git"
  "shared/search"
  "shared/file-tools"
  "shared/data-tools"
  "shared/network"
  "shared/neovim"
  "host/common"
)

setup_init_defaults() {
  DRY_RUN="${DRY_RUN:-false}"
  NO_INPUT="${NO_INPUT:-false}"
  SKIP_BOOTSTRAP="${SKIP_BOOTSTRAP:-false}"
  SKIP_PACKAGES="${SKIP_PACKAGES:-false}"
  SKIP_PROFILE_PACKAGES="${SKIP_PROFILE_PACKAGES:-false}"
  SKIP_MACOS="${SKIP_MACOS:-false}"
  SKIP_STOW="${SKIP_STOW:-false}"
  SKIP_VSCODE="${SKIP_VSCODE:-false}"
  SKIP_MANUAL_CHECK="${SKIP_MANUAL_CHECK:-false}"
  SKIP_SSH="${SKIP_SSH:-false}"

  if [[ -n "${NON_INTERACTIVE:-}" ]]; then
    NO_INPUT=true
  fi

  if [[ "${SETUP_INCLUDE_MANUAL_CHECK:-false}" != "true" ]]; then
    SKIP_MANUAL_CHECK=true
  fi

  if [[ "${SETUP_INCLUDE_SSH:-false}" != "true" ]]; then
    SKIP_SSH=true
  fi
}

info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

success() {
  echo -e "${GREEN}✓${NC} $*"
}

warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

error() {
  echo -e "${RED}✗${NC} $*" >&2
}

section() {
  echo
  echo -e "${GREEN}=== $* ===${NC}"
  echo
}

setup_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

setup_with_non_interactive_env() {
  if [[ "$NO_INPUT" == "true" ]]; then
    env NON_INTERACTIVE=1 NO_INPUT=true "$@"
  else
    "$@"
  fi
}

setup_run_install() {
  local config_files=$1
  shift
  local -a args=()

  if [[ "$DRY_RUN" == "true" ]]; then
    args+=(-d)
  fi

  if [[ $# -gt 0 ]]; then
    args+=("$@")
  fi

  CONFIG_FILES="$config_files" setup_with_non_interactive_env ./install.sh "${args[@]}"
}

setup_parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -d | --dry-run)
        DRY_RUN=true
        shift
        ;;
      --no-input)
        NO_INPUT=true
        shift
        ;;
      --skip-bootstrap)
        SKIP_BOOTSTRAP=true
        shift
        ;;
      --skip-packages)
        SKIP_PACKAGES=true
        SKIP_PROFILE_PACKAGES=true
        shift
        ;;
      --skip-profile-packages)
        SKIP_PROFILE_PACKAGES=true
        shift
        ;;
      --skip-macos)
        SKIP_MACOS=true
        shift
        ;;
      --skip-stow)
        SKIP_STOW=true
        shift
        ;;
      --skip-vscode)
        SKIP_VSCODE=true
        shift
        ;;
      --skip-manual-check)
        if [[ "${SETUP_INCLUDE_MANUAL_CHECK:-false}" != "true" ]]; then
          error "--skip-manual-check is only supported for personal setup"
          usage 1
        fi
        SKIP_MANUAL_CHECK=true
        shift
        ;;
      --skip-ssh)
        if [[ "${SETUP_INCLUDE_SSH:-false}" != "true" ]]; then
          error "--skip-ssh is only supported for personal setup"
          usage 1
        fi
        SKIP_SSH=true
        shift
        ;;
      -h | --help)
        usage 0
        ;;
      *)
        error "Unknown option: $1"
        usage 1
        ;;
    esac
  done
}

setup_require_macos() {
  if [[ "$(uname)" != "Darwin" ]]; then
    error "This script is for macOS only"
    exit 1
  fi
}

setup_run_bootstrap() {
  local -a args=()

  if [[ "$SKIP_BOOTSTRAP" == "true" ]]; then
    if ! setup_command_exists brew || ! setup_command_exists yq || ! setup_command_exists stow; then
      warning "Skipping bootstrap even though brew, yq, or stow is missing"
    else
      info "Skipping bootstrap"
    fi
    return 0
  fi

  if ! setup_command_exists brew || ! setup_command_exists yq || ! setup_command_exists stow; then
    if [[ "$DRY_RUN" == "true" ]]; then
      args+=(--dry-run)
    fi
    if [[ "$NO_INPUT" == "true" ]]; then
      args+=(--no-input)
    fi
    info "Running bootstrap to install essential tools..."
    if ! setup_with_non_interactive_env ./bootstrap.sh "${args[@]}"; then
      error "Bootstrap failed"
      exit 1
    fi
    success "Bootstrap completed"
  else
    success "Essential tools already installed"
  fi
}

setup_run_common_packages() {
  if [[ "$SKIP_PACKAGES" == "true" ]]; then
    info "Skipping shared and common package installation"
    return 0
  fi

  section "Installing shared and common packages"
  info "Installing packages from shared and host/common configurations..."
  if ! setup_run_install "${COMMON_SETUP_CONFIGS[*]}"; then
    error "Package installation failed"
    exit 1
  fi
  success "Packages installed"
}

setup_run_profile_packages() {
  if [[ "$SKIP_PACKAGES" == "true" || "$SKIP_PROFILE_PACKAGES" == "true" ]]; then
    info "Skipping ${SETUP_PROFILE_DISPLAY} package installation"
    return 0
  fi

  if [[ -f "$SETUP_PROFILE_CONFIG_PATH" ]]; then
    section "Installing ${SETUP_PROFILE_DISPLAY}-specific packages"
    info "Installing packages from ${SETUP_PROFILE_CONFIG} configuration..."
    if ! setup_run_install "$SETUP_PROFILE_CONFIG"; then
      error "${SETUP_PROFILE_DISPLAY_TITLE} package installation failed"
      exit 1
    fi
    success "${SETUP_PROFILE_DISPLAY_TITLE} packages installed"
  else
    warning "No ${SETUP_PROFILE_DISPLAY}-specific configuration found at $SETUP_PROFILE_CONFIG_PATH"
  fi
}

setup_run_manual_check() {
  if [[ "${SETUP_INCLUDE_MANUAL_CHECK:-false}" != "true" ]]; then
    return 0
  fi

  if [[ "$SKIP_MANUAL_CHECK" == "true" ]]; then
    info "Skipping manual application checks"
    return 0
  fi

  if [[ -f "_configs/host/manual-check.yaml" ]]; then
    section "Checking manually installed applications"
    info "Checking for required manual installations..."
    if ! setup_run_install "host/manual-check"; then
      warning "Some manual applications may be missing"
    fi
  fi
}

setup_run_macos() {
  local -a args=()

  if [[ "$SKIP_MACOS" == "true" ]]; then
    info "Skipping macOS configuration"
    return 0
  fi

  section "Applying macOS system settings"
  if [[ -f "$SETUP_MACOS_CONFIG" ]]; then
    info "Applying ${SETUP_PROFILE_DISPLAY} macOS settings..."
    if [[ "$DRY_RUN" == "true" ]]; then
      args+=(--dry-run)
    fi
    if [[ "$NO_INPUT" == "true" ]]; then
      args+=(--no-input)
    fi
    args+=("$SETUP_MACOS_CONFIG")
    if ! setup_with_non_interactive_env ./_macos/macos.sh "${args[@]}"; then
      error "macOS configuration failed"
      exit 1
    fi
    success "macOS settings applied"
  else
    warning "No ${SETUP_PROFILE_DISPLAY} macOS configuration found at $SETUP_MACOS_CONFIG"
    if [[ "$SETUP_PROFILE" == "work" ]]; then
      info "You may want to create one based on _macos/personal.yaml"
    fi
  fi
}

setup_run_stow() {
  if [[ "$SKIP_STOW" == "true" ]]; then
    info "Skipping stow"
    return 0
  fi

  section "Creating configuration symlinks"
  info "Running stow to create symlinks..."
  if ! setup_run_install "" -s; then
    error "Stow failed"
    exit 1
  fi
  success "Configuration symlinks created"
}

setup_run_vscode() {
  if [[ "$SKIP_VSCODE" == "true" ]]; then
    info "Skipping VSCode extension installation"
    return 0
  fi

  section "Installing VSCode extensions"
  if setup_command_exists code; then
    info "Installing VSCode extensions..."
    if ! setup_run_install "focus/vscode"; then
      warning "Some VSCode extensions may have failed to install"
    else
      success "VSCode extensions installed"
    fi
  else
    warning "VSCode not found, skipping extensions"
  fi
}

setup_run_ssh() {
  local -a args=()

  if [[ "${SETUP_INCLUDE_SSH:-false}" != "true" ]]; then
    return 0
  fi

  if [[ "$SKIP_SSH" == "true" ]]; then
    info "Skipping SSH setup"
    return 0
  fi

  section "SSH Configuration"
  if [[ -f "./setup-ssh-from-1password.sh" ]] && setup_command_exists op; then
    info "Setting up SSH configuration and keys from 1Password..."
    args=(--profile personal)
    if [[ "$DRY_RUN" == "true" ]]; then
      args+=(--dry-run)
    fi
    if [[ "$NO_INPUT" == "true" ]]; then
      args+=(--no-input)
    fi
    if setup_with_non_interactive_env ./setup-ssh-from-1password.sh "${args[@]}"; then
      success "SSH configuration completed"
    else
      warning "SSH setup encountered issues - you may need to run ./setup-ssh-from-1password.sh manually"
    fi
  else
    warning "1Password CLI not found or SSH setup script missing"
    echo "  To set up SSH later, run: ./setup-ssh-from-1password.sh --profile personal"
  fi
}

setup_print_completion() {
  section "Setup Complete!"
  if [[ "$DRY_RUN" == "true" ]]; then
    success "${SETUP_PROFILE_DISPLAY_TITLE} Mac setup dry run completed"
  else
    success "${SETUP_PROFILE_DISPLAY_TITLE} Mac setup completed successfully"
  fi
  echo
  print_next_steps
}

setup_main() {
  setup_init_defaults
  setup_parse_args "$@"
  setup_require_macos

  cd "$SETUP_SCRIPT_DIR" || exit 1
  section "$SETUP_TITLE"

  setup_run_bootstrap
  setup_run_common_packages
  setup_run_profile_packages
  setup_run_manual_check
  setup_run_macos
  setup_run_stow
  setup_run_vscode
  setup_run_ssh
  setup_print_completion
}
