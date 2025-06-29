#!/usr/bin/env bash
set -euo pipefail

# Configuration
YAML_FILE="tools.yaml"
REQUIRED_COMMANDS=("yq" "which")
STOW_DIRS=(aerospace bat gh git karabiner kitty nvim starship tmux zsh)

# Default values and argument parsing
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
STOW="${STOW:-false}"
FORCE="${FORCE:-false}"
UPDATE="${UPDATE:-false}"

command_exists() {
  type "$1" >/dev/null 2>&1
}

is_root() {
  [ "$(id -u 2>/dev/null || echo 1000)" -eq 0 ]
}

get_available_managers() {
  # Run the entire function in a subshell to ensure it returns 0
  (
    local -a available=()
    local -a unavailable=()

    # Get unique package managers from YAML
    local required_managers
    # Use || true to ensure the command doesn't cause an exit
    required_managers=$(yq '.tools[].manager' "$YAML_FILE" 2>/dev/null | sort -u || true)

    while read -r manager; do
      # Skip empty lines
      [[ -z "$manager" ]] && continue
      
      case "$manager" in
      "apt")
        if ! command_exists "apt-get"; then
          unavailable+=("apt: apt-get is not available on this system")
        elif ! is_root && [[ "$DRY_RUN" == "false" ]]; then
          unavailable+=("apt: requires root privileges - please run with sudo")
        else
          available+=("apt")
        fi
        ;;
      "arkade")
        if ! command_exists "arkade"; then
          unavailable+=("arkade: please install from https://github.com/alexellis/arkade")
        else
          available+=("arkade")
        fi
        ;;
      "brew")
        if ! command_exists "brew"; then
          unavailable+=("brew: please install from https://brew.sh")
        else
          available+=("brew")
        fi
        ;;
      "cargo")
        if ! command_exists "cargo"; then
          unavailable+=("cargo: please install from https://rustup.rs")
        else
          available+=("cargo")
        fi
        ;;
      "uv")
        if ! command_exists "uv"; then
          unavailable+=("uv: please install from https://github.com/astral-sh/uv")
        else
          available+=("uv")
        fi
        ;;
      *)
        unavailable+=("unknown package manager: $manager")
        ;;
      esac
    done <<<"$required_managers"

    # Report available and unavailable package managers to stderr
    if [ ${#available[@]} -gt 0 ]; then
      echo "Available package managers: ${available[*]}" >&2
    fi
    if [ ${#unavailable[@]} -gt 0 ]; then
      echo "Unavailable package managers:" >&2
      printf '  - %s\n' "${unavailable[@]}" >&2
    fi

    # Export available managers for use in installation (to stdout)
    printf '%s\n' "${available[@]}"
  ) || true
  
  # Always return success
  return 0
}

check_requirements() {
  local missing_commands=()

  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command_exists "$cmd"; then
      missing_commands+=("$cmd")
    fi
  done

  if [ ${#missing_commands[@]} -gt 0 ]; then
    error "Missing required commands: ${missing_commands[*]}"
    return 1
  fi
  return 0
}

run_stow() {
  if ! command_exists "stow"; then
    error "stow is not installed. Please install stow first."
    return 1
  fi

  local dotfiles_dir
  dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Debug: Show directory structure
  info "Dotfiles directory: $dotfiles_dir"
  info "Directory contents:"
  ls -la "$dotfiles_dir"

  local -a stow_opts=()
  stow_opts+=("--dir=$dotfiles_dir")
  stow_opts+=("--target=$HOME")
  [[ "$FORCE" == "true" ]] && stow_opts+=("--adopt")
  [[ "$DRY_RUN" == "true" ]] && stow_opts+=("--no")
  stow_opts+=("--verbose=1") # Maximum verbosity
  stow_opts+=("-R")

  for dir in "${STOW_DIRS[@]}"; do
    if [[ -d "$dotfiles_dir/$dir" ]]; then
      if stow "${stow_opts[@]}" "$dir"; then # Removed 2>/dev/null to see errors
        info "✓ Stowed $dir"
      else
        info "× Error stowing $dir"
      fi
    else
      info "! Directory $dir not found in $dotfiles_dir"
    fi
  done
}

error() {
  echo "ERROR: $*" >&2
  # Always return 1 to allow proper error propagation
  return 1
}

info() {
  local prefix=""
  [[ "$DRY_RUN" == "true" ]] && prefix="[DRY RUN] "

  if [[ "$VERBOSE" == "true" ]]; then
    echo "INFO: ${prefix}$*"
  else
    echo "${prefix}$*"
  fi
}

can_install_tool() {
  local tool=$1
  local manager
  manager=$(yq ".tools.${tool}.manager" "$YAML_FILE")

  [[ " ${AVAILABLE_MANAGERS[*]} " =~ \ ${manager}\  ]]
}

install_tool() {
  local tool=$1
  local manager
  local type
  local install_args
  local install_cmd

  manager=$(yq ".tools.${tool}.manager" "$YAML_FILE")
  type=$(yq ".tools.${tool}.type" "$YAML_FILE")
  install_args=$(yq ".tools.${tool}.install_args[]" "$YAML_FILE" | tr '\n' ' ')

  case "$manager" in
  "apt")
    case "$type" in
    "package")
      if [[ "$DRY_RUN" == "false" ]]; then
        apt-get update -qq || { error "Failed to update apt cache"; return 1; }
      fi
      install_cmd="apt-get install -y $install_args $tool"
      ;;
    *)
      info "Skipping $tool: unknown apt type: $type"
      return 0
      ;;
    esac
    ;;
  "arkade")
    case "$type" in
    "get")
      install_cmd="arkade get $tool $install_args"
      ;;
    "system")
      install_cmd="arkade system install $tool $install_args"
      ;;
    "install")
      install_cmd="arkade install $tool $install_args"
      ;;
    *)
      info "Skipping $tool: unknown arkade type: $type"
      return 0
      ;;
    esac
    ;;
  "brew")
    case "$type" in
    "cask")
      install_cmd="brew install --cask $install_args $tool"
      ;;
    "package")
      install_cmd="brew install $install_args $tool"
      ;;
    "tap")
      install_cmd="brew tap $install_args $tool"
      ;;
    *)
      info "Skipping $tool: unknown brew type: $type"
      return 0
      ;;
    esac
    ;;
  "cargo")
    case "$type" in
    "binary")
      install_cmd="cargo install $install_args $tool"
      ;;
    "git")
      install_cmd="cargo install --git $install_args $tool"
      ;;
    *)
      info "Skipping $tool: unknown cargo type: $type"
      return 0
      ;;
    esac
    ;;
  "uv")
    case "$type" in
    "tool")
      install_cmd="uv tool install $install_args $tool"
      ;;
    *)
      info "Skipping $tool: unknown uv type: $type"
      return 0
      ;;
    esac
    ;;
  *)
    info "Skipping $tool: unknown package manager: $manager"
    return 0
    ;;
  esac

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would execute: $install_cmd"
  else
    eval "$install_cmd"
  fi
  return 0
}

is_tool_installed() {
  local tool=$1
  local check_command
  check_command=$(yq ".tools.${tool}.check_command" "$YAML_FILE")

  if [ "$check_command" = "null" ]; then
    info "Skipping check for $tool: no check command specified"
    return 1 # Tool is not verified as installed if no check command
  fi

  # The check_command may contain environment variables like $HOME
  # We need to expand those while preserving quotes and spaces
  # Simply use eval directly on the check_command
  if eval "$check_command" >/dev/null 2>&1; then
    return 0 # Tool is installed
  else
    return 1 # Tool is not installed
  fi
}

main() {
  [[ "$DRY_RUN" == "true" ]] && info "Running in dry-run mode - no changes will be made"
  [[ "$FORCE" == "true" ]] && info "Running in force mode - existing files will be overwritten"

  # Check requirements and exit if they're not met
  if ! check_requirements; then
    return 1
  fi

  # Update package manager databases if in update mode
  if [[ "$UPDATE" == "true" ]]; then
    if command_exists brew; then
      info "Updating brew package database..."
      if [[ "$DRY_RUN" == "true" ]]; then
        info "Would execute: brew update"
      else
        brew update
      fi
    fi
  fi

  # Get available package managers
  AVAILABLE_MANAGERS=()
  while IFS= read -r manager; do
    # Skip empty lines
    [[ -n "$manager" ]] && AVAILABLE_MANAGERS+=("$manager")
  done < <(get_available_managers)

  if [ ${#AVAILABLE_MANAGERS[@]} -eq 0 ]; then
    info "No package managers available - nothing to do"
    return 0
  fi

  # Get all tools from YAML
  local tools
  tools=$(yq '.tools | keys | .[]' "$YAML_FILE")

  # Only process if we have tools
  if [[ -n "$tools" ]]; then
    while read -r tool; do
      if is_tool_installed "$tool"; then
        if [[ "$UPDATE" == "true" ]]; then
          manager=$(yq ".tools.${tool}.manager" "$YAML_FILE")
          type=$(yq ".tools.${tool}.type" "$YAML_FILE")
          
          case "$manager" in
          "brew")
            case "$type" in
            "package")
              if [[ "$DRY_RUN" == "true" ]]; then
                info "Would check: brew outdated $tool"
              else
                if brew outdated --quiet | grep -q "^$tool$"; then
                  info "Updating $tool (brew package)..."
                  brew upgrade "$tool"
                  info "✓ Updated $tool (brew package)"
                else
                  info "✓ $tool (brew package) is already up to date"
                fi
              fi
              ;;
            "cask")
              if [[ "$DRY_RUN" == "true" ]]; then
                info "Would check: brew outdated --cask $tool"
              else
                if brew outdated --cask --quiet | grep -q "^$tool$"; then
                  info "Updating $tool (brew cask)..."
                  brew upgrade --cask "$tool"
                  info "✓ Updated $tool (brew cask)"
                else
                  info "✓ $tool (brew cask) is already up to date"
                fi
              fi
              ;;
            "tap")
              info "✓ $tool (brew tap) - taps don't need updating"
              ;;
            *)
              info "✓ $tool (brew $type) is already installed"
              ;;
            esac
            ;;
          "cargo")
            if [[ "$FORCE" == "true" ]]; then
              if [[ "$DRY_RUN" == "true" ]]; then
                info "Would execute: cargo install --force $tool"
              else
                info "Force updating $tool (cargo binary)..."
                cargo install --force "$tool"
                info "✓ Force updated $tool (cargo binary)"
              fi
            else
              if [[ "$DRY_RUN" == "true" ]]; then
                info "Would check: cargo install-update -l | grep $tool"
              else
                # Check if cargo-update is installed
                if cargo install-update --version &>/dev/null; then
                  if cargo install-update -l | grep -q "^$tool.*Yes$"; then
                    info "Updating $tool (cargo binary)..."
                    cargo install-update "$tool"
                    info "✓ Updated $tool (cargo binary)"
                  else
                    info "✓ $tool (cargo binary) is already up to date"
                  fi
                else
                  info "✓ $tool (cargo binary) is installed - install 'cargo-update' to check for updates"
                  info "  Run: cargo install cargo-update"
                fi
              fi
            fi
            ;;
          "uv")
            if [[ "$FORCE" == "true" ]]; then
              if [[ "$DRY_RUN" == "true" ]]; then
                info "Would execute: uv tool install --force $tool"
              else
                info "Force updating $tool (uv tool)..."
                uv tool install --force "$tool"
                info "✓ Force updated $tool (uv tool)"
              fi
            else
              if [[ "$DRY_RUN" == "true" ]]; then
                info "Would check: uv tool install --upgrade $tool"
              else
                # Check if update is needed by capturing output
                local uv_output
                uv_output=$(uv tool install --upgrade "$tool" 2>&1)
                if echo "$uv_output" | grep -q "Updated"; then
                  info "Updated $tool (uv tool)"
                  info "✓ Successfully updated $tool (uv tool)"
                elif echo "$uv_output" | grep -q "up to date"; then
                  info "✓ $tool (uv tool) is already up to date"
                else
                  # If neither message found, show what happened
                  info "✓ $tool (uv tool) checked for updates"
                fi
              fi
            fi
            ;;
          "arkade")
            case "$type" in
            "get")
              if [[ "$FORCE" == "true" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                  info "Would execute: arkade get $tool"
                else
                  info "Force updating $tool (arkade get)..."
                  arkade get "$tool"
                  info "✓ Force updated $tool (arkade get)"
                fi
              else
                info "✓ $tool (arkade get) - arkade always downloads latest on 'get'"
              fi
              ;;
            *)
              info "✓ $tool (arkade $type) is already installed - update not supported"
              ;;
            esac
            ;;
          *)
            info "✓ $tool ($manager) is already installed - update not supported"
            ;;
          esac
        else
          manager=$(yq ".tools.${tool}.manager" "$YAML_FILE")
          type=$(yq ".tools.${tool}.type" "$YAML_FILE")
          case "$manager" in
          "brew")
            info "✓ $tool (brew $type) is already installed"
            ;;
          "arkade")
            info "✓ $tool (arkade $type) is already installed"
            ;;
          "cargo")
            info "✓ $tool (cargo $type) is already installed"
            ;;
          "uv")
            info "✓ $tool (uv $type) is already installed"
            ;;
          *)
            info "✓ $tool ($manager $type) is already installed"
            ;;
          esac
        fi
      elif can_install_tool "$tool"; then
        manager=$(yq ".tools.${tool}.manager" "$YAML_FILE")
        type=$(yq ".tools.${tool}.type" "$YAML_FILE")
        info "Installing $tool ($manager $type)..."
        if install_tool "$tool"; then
          info "✓ Successfully installed $tool ($manager $type)"
        else
          info "Failed to install $tool ($manager $type)"
        fi
      else
        manager=$(yq ".tools.${tool}.manager" "$YAML_FILE")
        info "Skipping $tool: $manager not available"
      fi
    done <<<"$tools"
  fi

  if [[ "$STOW" == "true" ]]; then
    info "Running stow..."
    run_stow
  fi
}

usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -d, --dry-run       Show what would be installed without making changes"
  echo "  -v, --verbose       Show detailed information and status messages"
  echo "  -s, --stow          Run stow after installation"
  echo "  -f, --force         Force stow to adopt existing files"
  echo "  -u, --update        Update already installed packages (brew only)"
  echo "  -h, --help          Show this help message"
  exit 1
}

# Check if we're being sourced for testing
SOURCE_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
  -d | --dry-run)
    DRY_RUN=true
    shift
    ;;
  -v | --verbose)
    VERBOSE=true
    shift
    ;;
  -s | --stow)
    STOW=true
    shift
    ;;
  -f | --force)
    FORCE=true
    shift
    ;;
  -u | --update)
    UPDATE=true
    shift
    ;;
  -h | --help)
    usage
    ;;
  --source-only)
    SOURCE_ONLY=true
    shift
    ;;
  *)
    usage
    ;;
  esac
done

# Only run main if not being sourced
if [[ "$SOURCE_ONLY" != "true" ]]; then
  # Set up error handling for non-test environments
  set -e
  trap 'exit 1' ERR
  main "$@"
fi
