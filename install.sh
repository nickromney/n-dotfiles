#!/usr/bin/env bash
set -euo pipefail

# Configuration
YAML_FILE="tools.yaml"
REQUIRED_COMMANDS=("yq" "which")

# Default values and argument parsing
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

get_available_managers() {
  local -a available=()
  local -a unavailable=()

  # Get unique package managers from YAML
  local required_managers
  required_managers=$(yq '.tools[].manager' "$YAML_FILE" | sort -u)

  while read -r manager; do
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

  # Report available and unavailable package managers
  if [ ${#available[@]} -gt 0 ]; then
    info "Available package managers: ${available[*]}"
  fi
  if [ ${#unavailable[@]} -gt 0 ]; then
    info "Unavailable package managers:"
    printf '  - %s\n' "${unavailable[@]}"
  fi

  # Export available managers for use in installation
  printf '%s\n' "${available[@]}"
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
  fi
}

error() {
  echo "ERROR: $*" >&2
  exit 1
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
        apt-get update -qq || error "Failed to update apt cache"
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
  "nvm")
    case "$type" in
    "node")
      # Source nvm first
      # shellcheck disable=SC1090
      . "$(brew --prefix nvm)/nvm.sh" || error "Failed to source nvm"
      install_cmd="nvm install $install_args"
      ;;
    *)
      info "Skipping $tool: unknown nvm type: $type"
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

is_root() {
  [ "$(id -u)" -eq 0 ]
}

is_tool_installed() {
  local tool=$1
  local check_command
  check_command=$(yq ".tools.${tool}.check_command" "$YAML_FILE")

  if [ "$check_command" = "null" ]; then
    info "Skipping $tool: no check command specified"
    return 0
  fi

  # Expand environment variables in check_command
  check_command=$(eval echo "$check_command")

  eval "$check_command" >/dev/null 2>&1
}

main() {
  [[ "$DRY_RUN" == "true" ]] && info "Running in dry-run mode - no changes will be made"

  check_requirements

  # Get available package managers
  AVAILABLE_MANAGERS=()
  while IFS= read -r manager; do
    AVAILABLE_MANAGERS+=("$manager")
  done < <(get_available_managers)

  if [ ${#AVAILABLE_MANAGERS[@]} -eq 0 ]; then
    info "No package managers available - nothing to do"
    exit 0
  fi

  # Get all tools from YAML
  local tools
  tools=$(yq '.tools | keys | .[]' "$YAML_FILE")

  while read -r tool; do
    if is_tool_installed "$tool"; then
      info "✓ $tool is already installed"
    elif can_install_tool "$tool"; then
      info "Installing $tool..."
      if install_tool "$tool"; then
        info "✓ Successfully installed $tool"
      else
        info "Failed to install $tool"
      fi
    else
      manager=$(yq ".tools.${tool}.manager" "$YAML_FILE")
      info "Skipping $tool: $manager not available"
    fi
  done <<<"$tools"
}

usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -d, --dry-run       Show what would be installed without making changes"
  echo "  -v, --verbose       Show detailed information and status messages"
  echo "  -h, --help          Show this help message"
  exit 1
}

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
  -h | --help)
    usage
    ;;
  *)
    usage
    ;;
  esac
done

main "$@"