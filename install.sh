#!/usr/bin/env bash
set -euo pipefail

# Configuration
DEFAULT_CONFIG_DIR="_configs"
CONFIG_DIR="${CONFIG_DIR:-}"
# VSCode CLI - can be overridden for variants like cursor, vscodium
VSCODE_CLI="${VSCODE_CLI:-}"
# Default to development tools only, but allow override via environment
# CONFIG_FILES can be set as environment variable with space-separated values
if [[ -n "${CONFIG_FILES+x}" ]]; then
  # CONFIG_FILES exists in environment (as a string)
  config_files_env="$CONFIG_FILES"
  if [[ -z "$config_files_env" ]]; then
    # It's empty, so use no files
    CONFIG_FILES=()
  else
    # Parse space-separated list into array
    IFS=' ' read -ra CONFIG_FILES <<<"$config_files_env"
  fi
  unset config_files_env
else
  # CONFIG_FILES not set in environment, use default
  CONFIG_FILES=("host/common")
fi
REQUIRED_COMMANDS=("yq" "which")
STOW_DIRS=(aerospace aws bat gh ghostty git kitty nushell nvim prettier starship tmux vscode zsh)

# Default values and argument parsing
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
STOW="${STOW:-false}"
FORCE="${FORCE:-false}"
UPDATE="${UPDATE:-false}"
CONFIG_FILES_SET_VIA_CLI="${CONFIG_FILES_SET_VIA_CLI:-false}"

command_exists() {
  type "$1" >/dev/null 2>&1
}

is_root() {
  [ "$(id -u 2>/dev/null || echo 1000)" -eq 0 ]
}

get_vscode_cli() {
  # Default to 'code' if not set
  local cli="${VSCODE_CLI:-code}"

  if command_exists "$cli"; then
    echo "$cli"
    return 0
  else
    error "VSCode CLI '$cli' not found. Set VSCODE_CLI environment variable to use a different binary (e.g., cursor)"
    return 1
  fi
}

get_available_managers() {
  # Run the entire function in a subshell to ensure it returns 0
  (
    local -a available=()
    local -a unavailable=()

    # Get unique package managers from YAML
    local required_managers
    # Use || true to ensure the command doesn't cause an exit
    required_managers=$(yq '.tools[].manager' "$1" 2>/dev/null | sort -u || true)

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
      "mas")
        if ! command_exists "mas"; then
          unavailable+=("mas: please install with 'brew install mas'")
        else
          available+=("mas")
        fi
        ;;
      "manual")
        # Manual manager is always "available" - it just checks, never installs
        available+=("manual")
        ;;
      "code")
        if ! get_vscode_cli >/dev/null 2>&1; then
          unavailable+=("code: VSCode CLI not found - please install VSCode or set VSCODE_CLI")
        else
          available+=("code")
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
    if [ ${#available[@]} -gt 0 ]; then
      printf '%s\n' "${available[@]}"
    fi
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

prepare_config_files() {
  local config_file
  local resolved_files=()

  # If no config files specified, report and exit
  if [ ${#CONFIG_FILES[@]} -eq 0 ]; then
    # Check if CONFIG_FILES was explicitly set to empty via environment
    if [[ "${CONFIG_FILES:-unset}" == "" ]]; then
      info "No configuration files specified (CONFIG_FILES was set to empty)."
      info "Use -c to add config files or unset CONFIG_FILES to use defaults."
    else
      info "No configuration files specified. Use -c to add config files."
    fi
    info "Example: $0 -c development -c productivity"
    return 1
  fi

  # Resolve each config file path
  for config_file in "${CONFIG_FILES[@]}"; do
    # Add .yaml extension if not present
    if [[ ! "$config_file" =~ \.(yaml|yml)$ ]]; then
      config_file="${config_file}.yaml"
    fi

    # Check if file exists directly
    if [[ -f "$config_file" ]]; then
      resolved_files+=("$config_file")
    elif [[ "$CONFIG_DIR" = /* ]] && [[ -f "$CONFIG_DIR/$config_file" ]]; then
      # Absolute CONFIG_DIR path
      resolved_files+=("$CONFIG_DIR/$config_file")
    else
      # Relative CONFIG_DIR path
      local script_dir
      script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

      if [[ -f "$CONFIG_DIR/$config_file" ]]; then
        resolved_files+=("$CONFIG_DIR/$config_file")
      elif [[ -f "$script_dir/$CONFIG_DIR/$config_file" ]]; then
        resolved_files+=("$script_dir/$CONFIG_DIR/$config_file")
      else
        error "Configuration file not found: $config_file"
        error "Searched in:"
        error "  - $config_file"
        error "  - $CONFIG_DIR/$config_file"
        error "  - $script_dir/$CONFIG_DIR/$config_file"
        return 1
      fi
    fi
  done

  # Export resolved files for use by other functions
  RESOLVED_CONFIG_FILES=("${resolved_files[@]}")
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
  local yaml_file=$2
  local manager
  manager=$(yq ".tools.${tool}.manager" "$yaml_file")

  [[ " ${AVAILABLE_MANAGERS[*]} " =~ \ ${manager}\  ]]
}

install_tool() {
  local tool=$1
  local yaml_file=$2
  local manager
  local type
  local install_args
  local install_cmd

  manager=$(yq ".tools.${tool}.manager" "$yaml_file")
  type=$(yq ".tools.${tool}.type" "$yaml_file")
  install_args=$(yq ".tools.${tool}.install_args[]" "$yaml_file" | tr '\n' ' ')

  case "$manager" in
  "apt")
    case "$type" in
    "package")
      if [[ "$DRY_RUN" == "false" ]]; then
        apt-get update -qq || {
          error "Failed to update apt cache"
          return 1
        }
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
  "mas")
    case "$type" in
    "app")
      local app_id
      app_id=$(yq ".tools.${tool}.app_id" "$yaml_file")
      if [[ -z "$app_id" || "$app_id" == "null" ]]; then
        error "No app_id specified for $tool"
        return 1
      fi
      install_cmd="mas install $app_id"
      ;;
    *)
      info "Skipping $tool: unknown mas type: $type"
      return 0
      ;;
    esac
    ;;
  "manual")
    # Manual tools are never installed, just reported
    local description doc_url
    description=$(yq ".tools.${tool}.description" "$yaml_file")
    doc_url=$(yq ".tools.${tool}.documentation_url" "$yaml_file")

    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would report: $tool requires manual installation"
      [[ "$doc_url" != "null" ]] && info "  Download from: $doc_url"
    else
      info "⚠️  $tool requires manual installation"
      [[ "$description" != "null" ]] && info "    $description"
      [[ "$doc_url" != "null" ]] && info "    Download from: $doc_url"
    fi
    return 0  # Always return success for manual tools
    ;;
  "code")
    case "$type" in
    "extension")
      # For VSCode extensions, we need the extension_id field
      local extension_id vscode_cli
      extension_id=$(yq ".tools.${tool}.extension_id" "$yaml_file")
      if [[ "$extension_id" == "null" || -z "$extension_id" ]]; then
        info "Skipping $tool: no extension_id specified"
        return 0
      fi
      vscode_cli=$(get_vscode_cli) || return 1
      install_cmd="$vscode_cli --install-extension $extension_id $install_args"
      ;;
    *)
      info "Skipping $tool: unknown code type: $type"
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
    # Special handling for mas to provide helpful error message
    if [[ "$manager" == "mas" ]]; then
      output=$(eval "$install_cmd" 2>&1)
      exit_code=$?
      echo "$output" | grep -v "Warning: "
      if [[ $exit_code -ne 0 ]]; then
        info "⚠️  Failed to install $tool from Mac App Store"
        info "    Common issues:"
        info "    - Not signed in: Open App Store app and sign in first"
        info "    - App already purchased on different account"
        info "    Then re-run: ./install.sh -c host/personal"
        return 0  # Don't fail the whole script
      fi
    # Special handling for brew to detect already installed packages
    elif [[ "$manager" == "brew" ]]; then
      output=$(eval "$install_cmd" 2>&1)
      exit_code=$?
      echo "$output"
      # Check if it was already installed (brew shows "Not upgrading" warning)
      if echo "$output" | grep -E -q "Warning: Not upgrading.*already installed|Warning: .* is already installed"; then
        return 2  # Special return code for already installed
      fi
      return $exit_code
    else
      eval "$install_cmd"
    fi
  fi
  return 0
}

is_tool_installed() {
  local tool=$1
  local yaml_file=$2
  local check_command manager
  check_command=$(yq ".tools.${tool}.check_command" "$yaml_file")
  manager=$(yq ".tools.${tool}.manager" "$yaml_file")

  if [ "$check_command" = "null" ]; then
    info "Skipping check for $tool: no check command specified"
    return 1 # Tool is not verified as installed if no check command
  fi

  # For code extensions, substitute the VSCode CLI in the check command
  if [[ "$manager" == "code" ]]; then
    local vscode_cli
    vscode_cli=$(get_vscode_cli) || return 1
    # Replace 'code' with the actual CLI in the check command
    check_command="${check_command//code --list-extensions/$vscode_cli --list-extensions}"
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

  # Set CONFIG_DIR to default if not specified
  if [[ -z "$CONFIG_DIR" ]]; then
    CONFIG_DIR="$DEFAULT_CONFIG_DIR"
  fi

  # Check requirements and exit if they're not met
  if ! check_requirements; then
    return 1
  fi

  # Prepare configuration files
  if ! prepare_config_files; then
    # If only stow was requested and no configs specified, that's OK
    if [[ "$STOW" == "true" ]] && [ ${#CONFIG_FILES[@]} -eq 0 ]; then
      info "No configuration files specified - proceeding with stow only"
      RESOLVED_CONFIG_FILES=()
    else
      return 1
    fi
  fi

  if [ ${#RESOLVED_CONFIG_FILES[@]} -gt 0 ]; then
    info "Using configuration files:"
    for config_file in "${RESOLVED_CONFIG_FILES[@]}"; do
      info "  - $config_file"
    done
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

  # Collect all required package managers from all config files
  local all_managers=()
  for config_file in "${RESOLVED_CONFIG_FILES[@]}"; do
    # Get available package managers for this config file
    while IFS= read -r manager; do
      # Skip empty lines and add unique managers
      if [[ -n "$manager" ]] && [[ ! " ${all_managers[*]:-} " =~ \ $manager\  ]]; then
        all_managers+=("$manager")
      fi
    done < <(get_available_managers "$config_file")
  done

  AVAILABLE_MANAGERS=("${all_managers[@]:-}")

  if [ ${#AVAILABLE_MANAGERS[@]} -eq 0 ]; then
    info "No package managers available - skipping package installation"
    # Don't return early - allow stow to run
  fi

  # Process each configuration file only if we have managers
  if [ ${#AVAILABLE_MANAGERS[@]} -gt 0 ]; then
    for CURRENT_CONFIG_FILE in "${RESOLVED_CONFIG_FILES[@]}"; do
      info ""
      info "Processing: $CURRENT_CONFIG_FILE"

      # Get all tools from this YAML file
      local tools
      # Handle empty or null tools section
      tools=$(yq '.tools | select(. != null) | keys | .[]' "$CURRENT_CONFIG_FILE" 2>/dev/null || echo "")

      # Only process if we have tools
      if [[ -n "$tools" ]]; then
        while read -r tool; do
          if is_tool_installed "$tool" "$CURRENT_CONFIG_FILE"; then
            if [[ "$UPDATE" == "true" ]]; then
              manager=$(yq ".tools.${tool}.manager" "$CURRENT_CONFIG_FILE")
              type=$(yq ".tools.${tool}.type" "$CURRENT_CONFIG_FILE")

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
              "mas")
                if [[ "$DRY_RUN" == "true" ]]; then
                  info "Would check: mas outdated"
                else
                  local app_id
                  app_id=$(yq ".tools.${tool}.app_id" "$CURRENT_CONFIG_FILE")
                  if mas outdated | grep -q "^$app_id"; then
                    info "Updating $tool (mas app)..."
                    mas upgrade "$app_id"
                    info "✓ Updated $tool (mas app)"
                  else
                    info "✓ $tool (mas app) is already up to date"
                  fi
                fi
                ;;
              "manual")
                # Manual tools don't update through the script
                info "✓ $tool (manual) - check vendor site for updates"
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
              "code")
                case "$type" in
                "extension")
                  if [[ "$DRY_RUN" == "true" ]]; then
                    info "Would check: code --list-extensions for updates"
                  else
                    # VSCode extensions auto-update by default
                    info "✓ $tool (code extension) - extensions auto-update in VSCode"
                  fi
                  ;;
                *)
                  info "✓ $tool (code $type) is already installed"
                  ;;
                esac
                ;;
              *)
                info "✓ $tool ($manager) is already installed - update not supported"
                ;;
              esac
            else
              manager=$(yq ".tools.${tool}.manager" "$CURRENT_CONFIG_FILE")
              type=$(yq ".tools.${tool}.type" "$CURRENT_CONFIG_FILE")
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
              "mas")
                info "✓ $tool (mas $type) is already installed"
                ;;
              "manual")
                info "✓ $tool (manual) is already installed"
                ;;
              "code")
                info "✓ $tool (code $type) is already installed"
                ;;
              *)
                info "✓ $tool ($manager $type) is already installed"
                ;;
              esac
            fi
          elif can_install_tool "$tool" "$CURRENT_CONFIG_FILE"; then
            manager=$(yq ".tools.${tool}.manager" "$CURRENT_CONFIG_FILE")
            type=$(yq ".tools.${tool}.type" "$CURRENT_CONFIG_FILE")
            info "Installing $tool ($manager $type)..."
            install_tool "$tool" "$CURRENT_CONFIG_FILE"
            install_result=$?
            if [[ $install_result -eq 0 ]]; then
              info "✓ Successfully installed $tool ($manager $type)"
            elif [[ $install_result -eq 2 ]]; then
              info "✓ $tool ($manager $type) was already up to date"
            else
              info "Failed to install $tool ($manager $type)"
            fi
          else
            manager=$(yq ".tools.${tool}.manager" "$CURRENT_CONFIG_FILE")
            info "Skipping $tool: $manager not available"
          fi
        done <<<"$tools"
      fi
    done # End of config file loop
  fi     # End of if AVAILABLE_MANAGERS check

  if [[ "$STOW" == "true" ]]; then
    info "Running stow..."
    run_stow
  fi
}

usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -c, --config <name>     Add configuration file to install (can be used multiple times)"
  echo "  -C, --config-dir <dir>  Specify configuration directory (default: _configs)"
  echo "  -d, --dry-run           Show what would be installed without making changes"
  echo "  -f, --force             Force stow to adopt existing files"
  echo "  -h, --help              Show this help message"
  echo "  -s, --stow              Run stow after installation"
  echo "  -u, --update            Update already installed packages (brew only)"
  echo "  -v, --verbose           Show detailed information and status messages"
  echo ""
  echo "Configuration files:"
  echo "  By default, 'host/common' tools are installed (essential Mac tools)."
  echo "  Use -c to specify different configuration files."
  echo "  Files are searched in the configuration directory."
  echo ""
  echo "Environment variables:"
  echo "  CONFIG_DIR    Configuration directory (can be absolute or relative path)"
  echo "  VSCODE_CLI    VSCode binary to use (default: code, e.g., cursor, vscodium)"
  echo ""
  echo "Examples:"
  echo "  $0                              # Install common host tools (default)"
  echo "  $0 -c focus/vscode              # Install VSCode extensions"
  echo "  $0 -c host/personal -c focus/vscode # Install personal tools + VSCode extensions"
  echo "  $0 -C /path/to/configs -c work  # Use custom config directory"
  echo "  CONFIG_DIR=./ $0 -c personal     # Use current directory for configs"
  echo "  VSCODE_CLI=cursor $0 -c focus/vscode # Install VSCode extensions for Cursor"
  echo "  $0 -s                            # Install common tools + run stow"
  echo "  CONFIG_FILES=\"\" $0 -s            # Run stow only (no package installation)"
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
  -c | --config)
    if [[ -n "$2" && ! "$2" =~ ^- ]]; then
      # Clear default if this is the first explicit config
      if [[ "$CONFIG_FILES_SET_VIA_CLI" == "false" ]]; then
        CONFIG_FILES=()
        CONFIG_FILES_SET_VIA_CLI=true
      fi
      CONFIG_FILES+=("$2")
      shift 2
    else
      echo "Error: --config requires a configuration name" >&2
      usage
    fi
    ;;
  -C | --config-dir)
    if [[ -n "$2" && ! "$2" =~ ^- ]]; then
      CONFIG_DIR="$2"
      shift 2
    else
      echo "Error: --config-dir requires a directory path" >&2
      usage
    fi
    ;;
  -h | --help)
    usage
    ;;
  --source-only)
    SOURCE_ONLY=true
    shift
    ;;
  *)
    echo "Error: Unknown option: $1" >&2
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
