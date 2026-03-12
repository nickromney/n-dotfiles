#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CONFIG_DIR="_configs"
CONFIG_DIR="${CONFIG_DIR:-}"
VSCODE_CLI="${VSCODE_CLI:-}"

if [[ -n "${CONFIG_FILES+x}" ]]; then
  config_files_env="$CONFIG_FILES"
  if [[ -z "$config_files_env" ]]; then
    CONFIG_FILES=()
  else
    IFS=' ' read -r -a CONFIG_FILES <<<"$config_files_env"
  fi
  unset config_files_env
else
  CONFIG_FILES=("host/common")
fi

REQUIRED_COMMANDS=("yq" "which")
STOW_DIRS=(aerospace aws bash bat claude codex factory gh ghostty git kitty nushell nvim prettier starship tmux vscode yazi zsh)

DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
STOW="${STOW:-false}"
FORCE="${FORCE:-false}"
UPDATE="${UPDATE:-false}"
CONFIG_FILES_SET_VIA_CLI="${CONFIG_FILES_SET_VIA_CLI:-false}"

INSTALL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_REPO_ROOT="${INSTALL_REPO_ROOT:-$(cd "$INSTALL_LIB_DIR/.." && pwd)}"
MANIFEST_GENERATOR="${MANIFEST_GENERATOR:-$INSTALL_REPO_ROOT/scripts/generate-install-manifests.sh}"

RESOLVED_CONFIG_FILES=()
MANIFEST_DIR=""
MANIFEST_BREWFILE=""
MANIFEST_ARKADE=""
MANIFEST_METADATA=""
AVAILABLE_MANAGERS=()
METADATA_LINES=()
DEPENDENCY_LINES=()
ARKADE_LINES=()
PENDING_BREW_PACKAGES=()
PENDING_BREW_CASKS=()
PENDING_APT_PACKAGES=()
PENDING_CARGO_TOOLS=()
PENDING_ARKADE_TOOLS=()
PENDING_ARKADE_TOOL_NAMES=()
PENDING_ARKADE_LABELS=()
BREW_UPDATE_FORMULAS=()
BREW_UPDATE_CASKS=()
MAS_UPDATE_LINES=()
BREW_BUNDLE_SKIP_ENV=()

command_exists() {
  type "$1" >/dev/null 2>&1
}

is_root() {
  [ "$(id -u 2>/dev/null || echo 1000)" -eq 0 ]
}

is_dry_run() {
  [[ "$DRY_RUN" == "true" ]]
}

is_verbose() {
  [[ "$VERBOSE" == "true" ]]
}

emit_log() {
  local level=$1
  shift
  local prefix=""
  is_dry_run && prefix="[DRY RUN] "
  echo "${prefix}${level}: $*"
}

error() {
  emit_log "Fail" "$*" >&2
  return 1
}

fail() {
  error "$@"
}

info() {
  emit_log "Info" "$@"
}

skip() {
  emit_log "Skip" "$@"
}

change() {
  emit_log "Change" "$@"
}

debug() {
  if is_verbose; then
    emit_log "Info" "$@"
  fi
}

timestamp_now() {
  date +%s
}

format_duration() {
  local total_seconds=$1
  local hours=0
  local minutes=0
  local seconds=0

  if [[ "$total_seconds" -lt 0 ]]; then
    total_seconds=0
  fi

  hours=$((total_seconds / 3600))
  minutes=$(((total_seconds % 3600) / 60))
  seconds=$((total_seconds % 60))

  if [[ "$hours" -gt 0 ]]; then
    printf '%sh %sm %ss\n' "$hours" "$minutes" "$seconds"
    return 0
  fi

  if [[ "$minutes" -gt 0 ]]; then
    printf '%sm %ss\n' "$minutes" "$seconds"
    return 0
  fi

  printf '%ss\n' "$seconds"
}

duration_since() {
  local started_at=$1
  local finished_at

  finished_at=$(timestamp_now)
  format_duration $((finished_at - started_at))
}

print_captured_output() {
  local output=$1
  local exit_code=$2

  if [[ -z "$output" ]]; then
    return 0
  fi

  if is_verbose || [[ $exit_code -ne 0 ]]; then
    printf '%s\n' "$output"
  fi
}

run_and_capture() {
  local output_file
  output_file=$(mktemp)

  set +e
  "$@" >"$output_file" 2>&1
  CAPTURE_EXIT_CODE=$?
  set -e

  CAPTURE_OUTPUT=$(cat "$output_file")
  rm -f "$output_file"

  print_captured_output "$CAPTURE_OUTPUT" "$CAPTURE_EXIT_CODE"
  return 0
}

run_eval_and_capture() {
  local command=$1
  local output_file
  output_file=$(mktemp)

  set +e
  eval "$command" >"$output_file" 2>&1
  CAPTURE_EXIT_CODE=$?
  set -e

  CAPTURE_OUTPUT=$(cat "$output_file")
  rm -f "$output_file"

  print_captured_output "$CAPTURE_OUTPUT" "$CAPTURE_EXIT_CODE"
  return 0
}

can_use_apt() {
  if ! command_exists "apt-get"; then
    return 1
  fi
  if is_root || is_dry_run; then
    return 0
  fi
  return 1
}

resolve_apt_package_name() {
  local tool=$1
  local yaml_file=$2
  local apt_package
  apt_package=$(yq ".tools.${tool}.apt_package" "$yaml_file" 2>/dev/null || echo "null")

  if [[ -z "$apt_package" || "$apt_package" == "null" ]]; then
    echo "$tool"
  else
    echo "$apt_package"
  fi
}

queue_brew_package() {
  local tool=$1
  local queued_tool
  for queued_tool in "${PENDING_BREW_PACKAGES[@]:-}"; do
    if [[ "$queued_tool" == "$tool" ]]; then
      return 1
    fi
  done
  PENDING_BREW_PACKAGES+=("$tool")
  return 0
}

queue_brew_cask() {
  local tool=$1
  local queued_tool
  for queued_tool in "${PENDING_BREW_CASKS[@]:-}"; do
    if [[ "$queued_tool" == "$tool" ]]; then
      return 1
    fi
  done
  PENDING_BREW_CASKS+=("$tool")
  return 0
}

queue_apt_package() {
  local package=$1
  local queued_package
  for queued_package in "${PENDING_APT_PACKAGES[@]:-}"; do
    if [[ "$queued_package" == "$package" ]]; then
      return 1
    fi
  done
  PENDING_APT_PACKAGES+=("$package")
  return 0
}

queue_cargo_tool() {
  local tool=$1
  local queued_tool
  for queued_tool in "${PENDING_CARGO_TOOLS[@]:-}"; do
    if [[ "$queued_tool" == "$tool" ]]; then
      return 1
    fi
  done
  PENDING_CARGO_TOOLS+=("$tool")
  return 0
}

queue_arkade_get_tool() {
  local tool=$1
  local install_args=${2:-}
  local queued_tool

  for queued_tool in "${PENDING_ARKADE_TOOL_NAMES[@]:-}"; do
    if [[ "$queued_tool" == "$tool" ]]; then
      return 1
    fi
  done

  if [[ -n "$install_args" ]]; then
    PENDING_ARKADE_TOOLS+=("$tool $install_args")
  else
    PENDING_ARKADE_TOOLS+=("$tool")
  fi
  PENDING_ARKADE_TOOL_NAMES+=("$tool")
  return 0
}

tool_update_is_skipped() {
  local tool=$1
  local yaml_file=$2
  local skip_update

  skip_update=$(yq ".tools.${tool}.skip_update" "$yaml_file" 2>/dev/null || echo "null")
  case "$skip_update" in
  true | yes | 1 | '"true"' | '"yes"' | '"1"')
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

get_vscode_cli() {
  local cli="${VSCODE_CLI:-code}"

  if command_exists "$cli"; then
    echo "$cli"
    return 0
  fi

  error "VSCode CLI '$cli' not found. Set VSCODE_CLI environment variable to use a different binary (for example: cursor)."
}

metadata_record_managers() {
  local source_file=$1

  if [[ "$source_file" == *.json ]]; then
    yq -r '.[].manager' "$source_file" 2>/dev/null || true
    return 0
  fi

  yq -r '.tools[].manager' "$source_file" 2>/dev/null || true
}

get_available_managers() {
  local source_file=$1
  (
    local -a available=()
    local -a unavailable=()
    local required_managers

    required_managers=$(metadata_record_managers "$source_file" | sort -u || true)

    while read -r manager; do
      [[ -z "$manager" ]] && continue
      case "$manager" in
      apt)
        if ! command_exists "apt-get"; then
          unavailable+=("apt: apt-get is not available on this system")
        elif ! is_root && ! is_dry_run; then
          unavailable+=("apt: requires root privileges - please run with sudo")
        else
          available+=("apt")
        fi
        ;;
      arkade)
        if command_exists "arkade"; then
          available+=("arkade")
        else
          unavailable+=("arkade: please install from https://github.com/alexellis/arkade")
        fi
        ;;
      brew)
        if command_exists "brew"; then
          available+=("brew")
        elif can_use_apt; then
          available+=("brew")
        elif command_exists "apt-get" && ! is_root && ! is_dry_run; then
          unavailable+=("brew: brew unavailable; apt fallback requires root privileges - please run with sudo")
        else
          unavailable+=("brew: please install from https://brew.sh")
        fi
        ;;
      cargo)
        if command_exists "cargo"; then
          available+=("cargo")
        else
          unavailable+=("cargo: please install from https://rustup.rs")
        fi
        ;;
      uv)
        if command_exists "uv"; then
          available+=("uv")
        else
          unavailable+=("uv: please install from https://github.com/astral-sh/uv")
        fi
        ;;
      mas)
        if command_exists "mas"; then
          available+=("mas")
        else
          unavailable+=("mas: please install with 'brew install mas'")
        fi
        ;;
      mise)
        if command_exists "mise"; then
          available+=("mise")
        else
          unavailable+=("mise: install via brew install mise")
        fi
        ;;
      code)
        if get_vscode_cli >/dev/null 2>&1; then
          available+=("code")
        else
          unavailable+=("code: VSCode CLI not found - please install VSCode or set VSCODE_CLI")
        fi
        ;;
      manual)
        available+=("manual")
        ;;
      *)
        unavailable+=("unknown package manager: $manager")
        ;;
      esac
    done <<<"$required_managers"

    if [[ ${#unavailable[@]} -gt 0 ]]; then
      echo "Unavailable package managers:" >&2
      printf '  - %s\n' "${unavailable[@]}" >&2
    fi

    if [[ ${#available[@]} -gt 0 ]]; then
      printf '%s\n' "${available[@]}"
    fi
  ) || true
}

check_requirements() {
  local missing_commands=()
  local cmd

  for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command_exists "$cmd"; then
      missing_commands+=("$cmd")
    fi
  done

  if [[ ${#missing_commands[@]} -gt 0 ]]; then
    error "Missing required commands: ${missing_commands[*]}"
    return 1
  fi

  return 0
}

prepare_config_files() {
  local config_file
  local resolved_files=()

  if [[ ${#CONFIG_FILES[@]} -eq 0 ]]; then
    if [[ "${CONFIG_FILES:-unset}" == "" ]]; then
      info "No configuration files specified (CONFIG_FILES was set to empty)."
      info "Use -c to add config files or unset CONFIG_FILES to use defaults."
    else
      info "No configuration files specified. Use -c to add config files."
    fi
    info "Example: $0 -c host/common -c focus/vscode"
    return 1
  fi

  for config_file in "${CONFIG_FILES[@]}"; do
    if [[ ! "$config_file" =~ \.(yaml|yml)$ ]]; then
      config_file="${config_file}.yaml"
    fi

    if [[ -f "$config_file" ]]; then
      resolved_files+=("$config_file")
    elif [[ "$CONFIG_DIR" = /* ]] && [[ -f "$CONFIG_DIR/$config_file" ]]; then
      resolved_files+=("$CONFIG_DIR/$config_file")
    elif [[ -f "$INSTALL_REPO_ROOT/$CONFIG_DIR/$config_file" ]]; then
      resolved_files+=("$INSTALL_REPO_ROOT/$CONFIG_DIR/$config_file")
    else
      error "Configuration file not found: $config_file"
      error "Searched in:"
      error "  - $config_file"
      error "  - $CONFIG_DIR/$config_file"
      error "  - $INSTALL_REPO_ROOT/$CONFIG_DIR/$config_file"
      return 1
    fi
  done

  RESOLVED_CONFIG_FILES=("${resolved_files[@]}")
  return 0
}

cleanup_generated_manifests() {
  if [[ -n "$MANIFEST_DIR" && -d "$MANIFEST_DIR" ]]; then
    rm -rf "$MANIFEST_DIR"
  fi
}

generate_manifests() {
  if [[ ${#RESOLVED_CONFIG_FILES[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ ! -x "$MANIFEST_GENERATOR" ]]; then
    error "Manifest generator not found or not executable: $MANIFEST_GENERATOR"
    return 1
  fi

  MANIFEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/n-dotfiles-manifests.XXXXXX")
  debug "Generating manifests into $MANIFEST_DIR"

  if is_dry_run; then
    info "Generating manifests for ${#RESOLVED_CONFIG_FILES[@]} config file(s)..."
  fi

  run_and_capture "$MANIFEST_GENERATOR" "$MANIFEST_DIR" "${RESOLVED_CONFIG_FILES[@]}"
  if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
    error "Manifest generation failed"
    return "$CAPTURE_EXIT_CODE"
  fi

  MANIFEST_BREWFILE="$MANIFEST_DIR/Brewfile"
  MANIFEST_ARKADE="$MANIFEST_DIR/arkade.tsv"
  MANIFEST_METADATA="$MANIFEST_DIR/metadata.json"

  if [[ ! -f "$MANIFEST_METADATA" ]]; then
    error "Metadata manifest was not generated: $MANIFEST_METADATA"
    return 1
  fi

  if [[ ! -f "$MANIFEST_BREWFILE" ]]; then
    : >"$MANIFEST_BREWFILE"
  fi

  if [[ ! -f "$MANIFEST_ARKADE" ]]; then
    : >"$MANIFEST_ARKADE"
  fi

  return 0
}

load_metadata_manifest() {
  METADATA_LINES=()
  DEPENDENCY_LINES=()

  if [[ ! -f "$MANIFEST_METADATA" ]]; then
    return 0
  fi

  while IFS=$'\t' read -r tool manager type check_command skip_update apt_package extension_id app_id description documentation_url category install_args; do
    [[ -z "$tool" ]] && continue
    METADATA_LINES+=("$tool"$'\t'"$manager"$'\t'"$type"$'\t'"$check_command"$'\t'"$skip_update"$'\t'"$apt_package"$'\t'"$extension_id"$'\t'"$app_id"$'\t'"$description"$'\t'"$documentation_url"$'\t'"$category"$'\t'"$install_args")
  done < <(
    yq -r '
      .[] |
      [
        .tool,
        .manager,
        .type,
        (.check_command // ""),
        ((.skip_update // false) | tostring),
        (.apt_package // "null"),
        (.extension_id // "null"),
        (.app_id // "null"),
        (.description // "null"),
        (.documentation_url // "null"),
        (.category // "null"),
        ((.install_args // []) | join(" "))
      ] | @tsv
    ' "$MANIFEST_METADATA"
  )

  while IFS=$'\t' read -r tool dep_name dep_check; do
    [[ -z "$tool" || -z "$dep_name" ]] && continue
    DEPENDENCY_LINES+=("$tool"$'\t'"$dep_name"$'\t'"$dep_check")
  done < <(
    # shellcheck disable=SC2016
    yq -r '
      .[] |
      .tool as $tool |
      (.dependencies // [])[]? |
      [$tool, .name, .check_command] | @tsv
    ' "$MANIFEST_METADATA"
  )
}

load_arkade_manifest() {
  ARKADE_LINES=()

  if [[ ! -f "$MANIFEST_ARKADE" ]]; then
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ARKADE_LINES+=("$line")
  done <"$MANIFEST_ARKADE"
}

metadata_count_for_manager() {
  local manager=$1
  local type=${2:-}
  local count=0
  local line
  local tool current_manager current_type

  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool current_manager current_type _ <<<"$line"
    if [[ "$current_manager" == "$manager" ]]; then
      if [[ -z "$type" || "$current_type" == "$type" ]]; then
        ((count += 1))
      fi
    fi
  done

  echo "$count"
}

find_metadata_line() {
  local requested_tool=$1
  local line
  local tool

  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool _ <<<"$line"
    if [[ "$tool" == "$requested_tool" ]]; then
      printf '%s\n' "$line"
      return 0
    fi
  done

  return 1
}

check_dependencies() {
  local tool=$1
  local dependency_line
  local dep_tool dep_name dep_check

  for dependency_line in "${DEPENDENCY_LINES[@]:-}"; do
    IFS=$'\t' read -r dep_tool dep_name dep_check <<<"$dependency_line"
    if [[ "$dep_tool" != "$tool" ]]; then
      continue
    fi

    if ! eval "$dep_check" >/dev/null 2>&1; then
      skip "$tool skipped - missing dependency: $dep_name"
      return 1
    fi
  done

  return 0
}

resolve_code_extensions_dir() {
  local vscode_cli=$1

  case "$vscode_cli" in
  *cursor*)
    echo "$HOME/.cursor/extensions"
    ;;
  *vscodium*)
    echo "$HOME/.vscode-oss/extensions"
    ;;
  *)
    echo "$HOME/.vscode/extensions"
    ;;
  esac
}

is_tool_installed_from_fields() {
  local tool=$1
  local manager=$2
  local type=$3
  local check_command=$4
  local extension_id=$5

  if [[ -z "$check_command" || "$check_command" == "null" ]]; then
    info "Skipping check for $tool: no check command specified"
    return 1
  fi

  if [[ "$manager" == "code" && "$type" == "extension" ]]; then
    local vscode_cli extensions_dir
    vscode_cli=$(get_vscode_cli) || return 1
    extensions_dir=$(resolve_code_extensions_dir "$vscode_cli")

    if [[ -n "$extension_id" && "$extension_id" != "null" ]]; then
      if [[ -d "$extensions_dir" ]] && ls -d "$extensions_dir/$extension_id"-* >/dev/null 2>&1; then
        return 0
      fi
    fi

    check_command="${check_command//code --list-extensions/$vscode_cli --list-extensions}"
  fi

  eval "$check_command" >/dev/null 2>&1
}

is_tool_installed() {
  local requested_tool=$1
  local source_file=${2:-}
  local line
  local manager type check_command extension_id

  if [[ -n "$source_file" && "$source_file" == *.json ]]; then
    MANIFEST_METADATA="$source_file"
    load_metadata_manifest
    line=$(find_metadata_line "$requested_tool") || return 1
    IFS=$'\t' read -r _ manager type check_command _ _ extension_id _ _ _ _ _ <<<"$line"
    is_tool_installed_from_fields "$requested_tool" "$manager" "$type" "$check_command" "$extension_id"
    return $?
  fi

  check_command=$(yq ".tools.${requested_tool}.check_command" "$source_file")
  manager=$(yq ".tools.${requested_tool}.manager" "$source_file")
  type=$(yq ".tools.${requested_tool}.type" "$source_file")

  if [[ "$check_command" == "null" ]]; then
    info "Skipping check for $requested_tool: no check command specified"
    return 1
  fi

  if [[ "$manager" == "code" && "$type" == "extension" ]]; then
    extension_id=$(yq ".tools.${requested_tool}.extension_id" "$source_file" 2>/dev/null || echo "")
  else
    extension_id=""
  fi

  is_tool_installed_from_fields "$requested_tool" "$manager" "$type" "$check_command" "$extension_id"
}

can_install_tool() {
  local tool=$1
  local yaml_file=$2
  local manager

  manager=$(yq ".tools.${tool}.manager" "$yaml_file" 2>/dev/null || echo "null")
  [[ " ${AVAILABLE_MANAGERS[*]} " =~ \ ${manager}\  ]]
}

install_tool() {
  local tool=$1
  local yaml_file=$2
  local manager
  local type
  local install_args
  local install_cmd
  local output=""
  local exit_code=0

  manager=$(yq ".tools.${tool}.manager" "$yaml_file")
  type=$(yq ".tools.${tool}.type" "$yaml_file")
  install_args=$(yq ".tools.${tool}.install_args[]" "$yaml_file" 2>/dev/null | tr '\n' ' ')

  case "$manager" in
  apt)
    case "$type" in
    package)
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
  arkade)
    case "$type" in
    get)
      queue_arkade_get_tool "$tool" "$install_args" || true
      return 0
      ;;
    system)
      install_cmd="arkade system install $tool $install_args"
      ;;
    install)
      install_cmd="arkade install $tool $install_args"
      ;;
    *)
      info "Skipping $tool: unknown arkade type: $type"
      return 0
      ;;
    esac
    ;;
  brew)
    if command_exists "brew"; then
      case "$type" in
      cask)
        install_cmd="brew install --cask $install_args $tool"
        ;;
      package)
        install_cmd="brew install $install_args $tool"
        ;;
      tap)
        install_cmd="brew tap $install_args $tool"
        ;;
      *)
        info "Skipping $tool: unknown brew type: $type"
        return 0
        ;;
      esac
    else
      case "$type" in
      package)
        if can_use_apt; then
          local apt_package
          apt_package=$(resolve_apt_package_name "$tool" "$yaml_file")
          if [[ "$DRY_RUN" == "false" ]]; then
            apt-get update -qq || {
              error "Failed to update apt cache"
              return 1
            }
          fi
          info "brew unavailable, using apt fallback for $tool"
          install_cmd="apt-get install -y $install_args $apt_package"
        elif command_exists "apt-get"; then
          info "Skipping $tool: brew unavailable and apt fallback requires root privileges"
          return 0
        else
          info "Skipping $tool: brew unavailable and apt-get not found"
          return 0
        fi
        ;;
      *)
        info "Skipping $tool: brew unavailable; apt fallback supports package type only"
        return 0
        ;;
      esac
    fi
    ;;
  cargo)
    case "$type" in
    binary)
      install_cmd="cargo install $install_args $tool"
      ;;
    git)
      install_cmd="cargo install --git $install_args $tool"
      ;;
    *)
      info "Skipping $tool: unknown cargo type: $type"
      return 0
      ;;
    esac
    ;;
  uv)
    case "$type" in
    tool)
      install_cmd="uv tool install $install_args $tool"
      ;;
    *)
      info "Skipping $tool: unknown uv type: $type"
      return 0
      ;;
    esac
    ;;
  mise)
    case "$type" in
    runtime | tool)
      install_cmd="mise install $install_args $tool"
      ;;
    *)
      info "Skipping $tool: unknown mise type: $type"
      return 0
      ;;
    esac
    ;;
  mas)
    case "$type" in
    app)
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
  manual)
    local description doc_url
    description=$(yq ".tools.${tool}.description" "$yaml_file" 2>/dev/null || echo "null")
    doc_url=$(yq ".tools.${tool}.documentation_url" "$yaml_file" 2>/dev/null || echo "null")

    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would report: $tool requires manual installation"
      [[ "$doc_url" != "null" ]] && info "  Download from: $doc_url"
    else
      info "$tool requires manual installation"
      [[ "$description" != "null" ]] && info "  $description"
      [[ "$doc_url" != "null" ]] && info "  Download from: $doc_url"
    fi
    return 0
    ;;
  code)
    case "$type" in
    extension)
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
    return 0
  fi

  if [[ "$manager" == "mas" ]]; then
    output=$(eval "$install_cmd" 2>&1)
    exit_code=$?
    echo "$output" | grep -v "Warning: "
    if [[ $exit_code -ne 0 ]]; then
      info "Failed to install $tool from Mac App Store"
      info "Then re-run: ./install.sh -c host/personal"
      return 0
    fi
    return 0
  fi

  if [[ "$manager" == "brew" ]]; then
    output=$(eval "$install_cmd" 2>&1)
    exit_code=$?
    echo "$output"
    if echo "$output" | grep -E -q "Warning: Not upgrading.*already installed|Warning: .* is already installed"; then
      return 2
    fi
    return $exit_code
  fi

  if [[ "$manager" == "code" ]]; then
    output=$(eval "$install_cmd" 2>&1)
    exit_code=$?
    echo "$output"
    if echo "$output" | grep -qi "is already installed"; then
      return 2
    fi
    if [[ $exit_code -ne 0 ]]; then
      echo "Warning: VSCode extension installation failed (exit code $exit_code)"
      echo "This may be a VSCode/Electron bug. Try manually: $install_cmd"
      return 1
    fi
    return 0
  fi

  eval "$install_cmd"
}

run_stow() {
  if ! command_exists "stow"; then
    error "stow is not installed. Please install stow first."
    return 1
  fi

  local -a stow_opts=()
  local dir

  stow_opts+=("--dir=$INSTALL_REPO_ROOT")
  stow_opts+=("--target=$HOME")
  [[ "$FORCE" == "true" ]] && stow_opts+=("--adopt")
  [[ "$DRY_RUN" == "true" ]] && stow_opts+=("--no")
  stow_opts+=("--verbose=1")
  stow_opts+=("-R")

  for dir in "${STOW_DIRS[@]}"; do
    if [[ ! -d "$INSTALL_REPO_ROOT/$dir" ]]; then
      debug "Stow directory not present: $dir"
      continue
    fi

    if stow "${stow_opts[@]}" "$dir"; then
      change "Stowed $dir"
    else
      error "Error stowing $dir"
      return 1
    fi
  done
}

join_by_space() {
  local IFS=' '
  echo "$*"
}

counted_noun() {
  local count=$1
  local singular=$2
  local plural=${3:-${singular}s}

  if [[ "$count" -eq 1 ]]; then
    printf '%s %s\n' "$count" "$singular"
    return 0
  fi

  printf '%s %s\n' "$count" "$plural"
}

format_compact_list() {
  local limit=$1
  shift

  local items=("$@")
  local count=${#items[@]}
  local slice_count=$count

  if [[ $slice_count -gt $limit ]]; then
    slice_count=$limit
  fi

  local output=""
  local idx
  for ((idx = 0; idx < slice_count; idx++)); do
    if [[ -n "$output" ]]; then
      output+=", "
    fi
    output+="${items[$idx]}"
  done

  if [[ $count -gt $limit ]]; then
    output+=" (+$((count - limit)) more)"
  fi

  printf '%s\n' "$output"
}

metadata_line_should_skip_update() {
  local line=$1
  local skip_update

  IFS=$'\t' read -r _ _ _ _ skip_update _ _ _ _ _ _ _ <<<"$line"
  [[ "$skip_update" == "true" ]]
}

metadata_line_install_args() {
  local line=$1
  local install_args
  IFS=$'\t' read -r _ _ _ _ _ _ _ _ _ _ _ install_args <<<"$line"
  printf '%s\n' "$install_args"
}

metadata_line_apt_package() {
  local line=$1
  local apt_package
  IFS=$'\t' read -r _ _ _ _ _ apt_package _ _ _ _ _ _ <<<"$line"
  if [[ -z "$apt_package" || "$apt_package" == "null" ]]; then
    echo ""
  else
    echo "$apt_package"
  fi
}

metadata_line_extension_id() {
  local line=$1
  local extension_id
  IFS=$'\t' read -r _ _ _ _ _ _ extension_id _ _ _ _ _ <<<"$line"
  if [[ -z "$extension_id" || "$extension_id" == "null" ]]; then
    echo ""
  else
    echo "$extension_id"
  fi
}

metadata_line_app_id() {
  local line=$1
  local app_id
  IFS=$'\t' read -r _ _ _ _ _ _ _ app_id _ _ _ _ <<<"$line"
  if [[ -z "$app_id" || "$app_id" == "null" ]]; then
    echo ""
  else
    echo "$app_id"
  fi
}

prepare_brew_bundle_skip_env() {
  BREW_BUNDLE_SKIP_ENV=()

  local -a skip_formulae=()
  local -a skip_casks=()
  local -a skip_mas=()
  local -a skipped_tools=()
  local line tool manager type check_command extension_id

  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool manager type check_command _ _ extension_id _ _ _ _ _ <<<"$line"

    case "$manager:$type" in
    brew:package)
      if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
        skip_formulae+=("$tool")
        skipped_tools+=("$tool")
      fi
      ;;
    brew:cask)
      if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
        skip_casks+=("$tool")
        skipped_tools+=("$tool")
      fi
      ;;
    mas:app)
      if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
        skip_mas+=("$tool")
        skipped_tools+=("$tool")
      fi
      ;;
    esac
  done

  if [[ ${#skip_formulae[@]} -gt 0 ]]; then
    BREW_BUNDLE_SKIP_ENV+=("HOMEBREW_BUNDLE_BREW_SKIP=${skip_formulae[*]}")
  fi

  if [[ ${#skip_casks[@]} -gt 0 ]]; then
    BREW_BUNDLE_SKIP_ENV+=("HOMEBREW_BUNDLE_CASK_SKIP=${skip_casks[*]}")
  fi

  if [[ ${#skip_mas[@]} -gt 0 ]]; then
    BREW_BUNDLE_SKIP_ENV+=("HOMEBREW_BUNDLE_MAS_SKIP=${skip_mas[*]}")
  fi

  if [[ ${#skipped_tools[@]} -gt 0 ]]; then
    local entry_word="entries"
    if [[ ${#skipped_tools[@]} -eq 1 ]]; then
      entry_word="entry"
    fi
    skip "Homebrew bundle omitting ${#skipped_tools[@]} already satisfied ${entry_word}"
    if is_verbose; then
      info "Homebrew bundle omissions: ${skipped_tools[*]}"
    fi
  fi
}

run_brew_install() {
  if ! command_exists "brew"; then
    return 0
  fi

  local tap_count formula_count cask_count mas_count total_count
  tap_count=$(metadata_count_for_manager "brew" "tap")
  formula_count=$(metadata_count_for_manager "brew" "package")
  cask_count=$(metadata_count_for_manager "brew" "cask")
  mas_count=$(metadata_count_for_manager "mas")
  total_count=$((tap_count + formula_count + cask_count + mas_count))

  if [[ $total_count -eq 0 ]]; then
    return 0
  fi

  info "Applying Homebrew bundle ($tap_count taps, $formula_count formulae, $cask_count casks, $mas_count App Store apps)..."
  prepare_brew_bundle_skip_env

  if is_dry_run; then
    info "Would execute: brew bundle --file=\"$MANIFEST_BREWFILE\""
    return 0
  fi

  if [[ ${#BREW_BUNDLE_SKIP_ENV[@]} -gt 0 ]]; then
    run_and_capture env "${BREW_BUNDLE_SKIP_ENV[@]}" brew bundle --file="$MANIFEST_BREWFILE"
  else
    run_and_capture brew bundle --file="$MANIFEST_BREWFILE"
  fi
  if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
    error "Homebrew bundle failed"
    return "$CAPTURE_EXIT_CODE"
  fi

  change "Homebrew bundle applied"
}

queue_brew_updates() {
  BREW_UPDATE_FORMULAS=()
  BREW_UPDATE_CASKS=()
  MAS_UPDATE_LINES=()

  local installed_formulas=""
  local installed_casks=""
  local outdated_formulas=""
  local outdated_casks=""
  local line
  local tool manager type check_command skip_update extension_id
  local -a managed_taps=()
  local -a update_disabled=()
  local -a up_to_date_formulas=()
  local -a up_to_date_casks=()
  local -a not_installed_formulas=()
  local -a not_installed_casks=()
  local -a unsupported_types=()

  if ! command_exists "brew"; then
    return 0
  fi

  installed_formulas=$(brew list --formula 2>/dev/null || true)
  installed_casks=$(brew list --cask 2>/dev/null || true)
  outdated_formulas=$(brew outdated --formula 2>/dev/null || true)
  outdated_casks=$(brew outdated --cask 2>/dev/null || true)

  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool manager type check_command skip_update _ extension_id _ _ _ _ _ <<<"$line"

    if [[ "$manager" == "mas" ]]; then
      MAS_UPDATE_LINES+=("$line")
      continue
    fi

    if [[ "$manager" != "brew" ]]; then
      continue
    fi

    if [[ "$type" == "tap" ]]; then
      managed_taps+=("$tool")
      continue
    fi

    if [[ "$skip_update" == "true" ]]; then
      update_disabled+=("$tool ($type)")
      continue
    fi

    case "$type" in
    package)
      if echo "$installed_formulas" | grep -qx "$tool"; then
        if echo "$outdated_formulas" | grep -qx "$tool"; then
          BREW_UPDATE_FORMULAS+=("$tool")
        else
          up_to_date_formulas+=("$tool")
        fi
      else
        not_installed_formulas+=("$tool")
      fi
      ;;
    cask)
      if echo "$installed_casks" | grep -qx "$tool"; then
        if echo "$outdated_casks" | grep -qx "$tool"; then
          BREW_UPDATE_CASKS+=("$tool")
        else
          up_to_date_casks+=("$tool")
        fi
      else
        not_installed_casks+=("$tool")
      fi
      ;;
    *)
      unsupported_types+=("$tool ($type)")
      ;;
    esac
  done

  if [[ ${#up_to_date_formulas[@]} -gt 0 ]]; then
    skip "$(counted_noun "${#up_to_date_formulas[@]}" "Homebrew formula" "Homebrew formulae") already up to date"
    if is_verbose; then
      info "Up-to-date Homebrew formulae: $(format_compact_list 20 "${up_to_date_formulas[@]}")"
    fi
  fi

  if [[ ${#up_to_date_casks[@]} -gt 0 ]]; then
    skip "$(counted_noun "${#up_to_date_casks[@]}" "Homebrew cask") already up to date"
    if is_verbose; then
      info "Up-to-date Homebrew casks: $(format_compact_list 20 "${up_to_date_casks[@]}")"
    fi
  fi

  if [[ ${#managed_taps[@]} -gt 0 ]]; then
    skip "Homebrew taps are managed repositories (${#managed_taps[@]}): $(format_compact_list 5 "${managed_taps[@]}")"
  fi

  if [[ ${#update_disabled[@]} -gt 0 ]]; then
    skip "Homebrew updates disabled by configuration (${#update_disabled[@]}): $(format_compact_list 5 "${update_disabled[@]}")"
  fi

  if [[ ${#not_installed_formulas[@]} -gt 0 ]]; then
    skip "Homebrew formulae not installed via Homebrew (${#not_installed_formulas[@]}): $(format_compact_list 5 "${not_installed_formulas[@]}")"
  fi

  if [[ ${#not_installed_casks[@]} -gt 0 ]]; then
    skip "Homebrew casks not installed via Homebrew (${#not_installed_casks[@]}): $(format_compact_list 5 "${not_installed_casks[@]}")"
  fi

  if [[ ${#unsupported_types[@]} -gt 0 ]]; then
    skip "Homebrew entries with unsupported update types (${#unsupported_types[@]}): $(format_compact_list 5 "${unsupported_types[@]}")"
  fi
}

run_brew_update() {
  if ! command_exists "brew"; then
    return 0
  fi

  local started_at
  local elapsed

  queue_brew_updates

  if [[ ${#BREW_UPDATE_FORMULAS[@]} -eq 0 && ${#BREW_UPDATE_CASKS[@]} -eq 0 ]]; then
    return 0
  fi

  info "Refreshing Homebrew metadata..."
  if is_dry_run; then
    info "Would execute: brew update"
  else
    started_at=$(timestamp_now)
    run_and_capture brew update
    if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
      error "brew update failed"
      return "$CAPTURE_EXIT_CODE"
    fi
    elapsed=$(duration_since "$started_at")
    info "Refreshed Homebrew metadata in $elapsed"
  fi

  if [[ ${#BREW_UPDATE_FORMULAS[@]} -gt 0 ]]; then
    info "Updating $(counted_noun "${#BREW_UPDATE_FORMULAS[@]}" "Homebrew formula" "Homebrew formulae")..."
    if is_dry_run; then
      info "Would execute: brew upgrade $(join_by_space "${BREW_UPDATE_FORMULAS[@]}")"
    else
      started_at=$(timestamp_now)
      run_and_capture brew upgrade "${BREW_UPDATE_FORMULAS[@]}"
      if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
        error "brew formula upgrade failed"
        return "$CAPTURE_EXIT_CODE"
      fi
      elapsed=$(duration_since "$started_at")
      change "Updated $(counted_noun "${#BREW_UPDATE_FORMULAS[@]}" "Homebrew formula" "Homebrew formulae"): $(format_compact_list 10 "${BREW_UPDATE_FORMULAS[@]}") in $elapsed"
    fi
  fi

  if [[ ${#BREW_UPDATE_CASKS[@]} -gt 0 ]]; then
    info "Updating $(counted_noun "${#BREW_UPDATE_CASKS[@]}" "Homebrew cask")..."
    if is_dry_run; then
      info "Would execute: brew upgrade --cask $(join_by_space "${BREW_UPDATE_CASKS[@]}")"
    else
      started_at=$(timestamp_now)
      run_and_capture brew upgrade --cask "${BREW_UPDATE_CASKS[@]}"
      if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
        error "brew cask upgrade failed"
        return "$CAPTURE_EXIT_CODE"
      fi
      elapsed=$(duration_since "$started_at")
      change "Updated $(counted_noun "${#BREW_UPDATE_CASKS[@]}" "Homebrew cask"): $(format_compact_list 10 "${BREW_UPDATE_CASKS[@]}") in $elapsed"
    fi
  fi
}

run_mas_update() {
  if ! command_exists "mas"; then
    return 0
  fi

  local outdated=""
  local line
  local tool manager type app_id
  local -a selected_ids=()
  local -a mas_update_lines=()

  if [[ "${MAS_UPDATE_LINES+set}" == "set" ]]; then
    set +u
    mas_update_lines=("${MAS_UPDATE_LINES[@]}")
    set -u
  fi

  if [[ ${#mas_update_lines[@]} -eq 0 ]]; then
    return 0
  fi

  outdated=$(mas outdated 2>/dev/null || true)
  for line in "${mas_update_lines[@]}"; do
    IFS=$'\t' read -r tool manager type _ _ _ _ _ _ _ _ _ <<<"$line"
    if [[ -z "$tool" || "$manager" != "mas" || "$type" != "app" ]]; then
      skip "Ignoring malformed App Store manifest entry"
      continue
    fi

    app_id=$(metadata_line_app_id "$line")

    if [[ -z "$app_id" ]]; then
      skip "$tool (mas app) has no app_id"
      continue
    fi

    if echo "$outdated" | grep -q "^$app_id"; then
      selected_ids+=("$app_id")
    else
      skip "$tool (mas app) already up to date"
    fi
  done

  if [[ ${#selected_ids[@]} -eq 0 ]]; then
    return 0
  fi

  if is_dry_run; then
    local app_id
    for app_id in "${selected_ids[@]}"; do
      info "Would execute: mas upgrade $app_id"
    done
    return 0
  fi

  local app_id
  for app_id in "${selected_ids[@]}"; do
    run_and_capture mas upgrade "$app_id"
    if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
      error "mas upgrade failed for app id $app_id"
      return "$CAPTURE_EXIT_CODE"
    fi
  done

  change "Updated ${#selected_ids[@]} App Store app(s)"
}

run_apt_package_batch() {
  local action=$1
  shift
  local packages=("$@")

  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  if ! can_use_apt; then
    if command_exists "apt-get"; then
      skip "apt requires root privileges for $action"
    fi
    return 0
  fi

  if [[ "$action" == "install" ]]; then
    if is_dry_run; then
      info "Would execute: apt-get update -qq"
      info "Would execute: apt-get install -y $(join_by_space "${packages[@]}")"
      return 0
    fi

    run_and_capture apt-get update -qq
    if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
      error "apt-get update failed"
      return "$CAPTURE_EXIT_CODE"
    fi

    run_and_capture apt-get install -y "${packages[@]}"
    if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
      error "apt-get install failed"
      return "$CAPTURE_EXIT_CODE"
    fi

    change "Installed ${#packages[@]} apt package(s)"
    return 0
  fi

  if is_dry_run; then
    info "Would execute: apt-get update -qq"
    info "Would execute: apt-get install --only-upgrade -y $(join_by_space "${packages[@]}")"
    return 0
  fi

  run_and_capture apt-get update -qq
  if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
    error "apt-get update failed"
    return "$CAPTURE_EXIT_CODE"
  fi

  run_and_capture apt-get install --only-upgrade -y "${packages[@]}"
  if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
    error "apt package update failed"
    return "$CAPTURE_EXIT_CODE"
  fi

  change "Updated ${#packages[@]} apt package(s)"
}

collect_brew_fallback_packages() {
  BREW_FALLBACK_INSTALL_PACKAGES=()
  BREW_FALLBACK_UPDATE_PACKAGES=()

  local line
  local tool manager type check_command skip_update apt_package extension_id

  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool manager type check_command skip_update _ extension_id _ _ _ _ _ <<<"$line"

    if [[ "$manager" != "brew" || "$type" != "package" ]]; then
      continue
    fi

    apt_package=$(metadata_line_apt_package "$line")
    [[ -z "$apt_package" ]] && apt_package="$tool"

    if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
      if [[ "$UPDATE" == "true" ]]; then
        if [[ "$skip_update" == "true" ]]; then
          skip "$tool (brew package via apt fallback) update disabled by configuration"
        else
          BREW_FALLBACK_UPDATE_PACKAGES+=("$apt_package")
        fi
      fi
    else
      if [[ "$UPDATE" == "true" ]]; then
        skip "$tool (brew package via apt fallback) is not installed"
      else
        BREW_FALLBACK_INSTALL_PACKAGES+=("$apt_package")
      fi
    fi
  done
}

queue_arkade_tools() {
  PENDING_ARKADE_TOOLS=()
  PENDING_ARKADE_LABELS=()

  local line
  local tool install_args
  local metadata_line
  local manager type check_command skip_update extension_id

  for line in "${ARKADE_LINES[@]:-}"; do
    IFS=$'\t' read -r tool install_args <<<"$line"
    metadata_line=$(find_metadata_line "$tool") || continue
    IFS=$'\t' read -r _ manager type check_command skip_update _ extension_id _ _ _ _ _ <<<"$metadata_line"

    if ! check_dependencies "$tool"; then
      continue
    fi

    if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
      if [[ "$UPDATE" == "true" ]]; then
        if [[ "$skip_update" == "true" ]]; then
          skip "$tool (arkade get) update disabled by configuration"
        else
          PENDING_ARKADE_TOOLS+=("$tool"$'\t'"$install_args")
          PENDING_ARKADE_LABELS+=("$tool")
        fi
      else
        skip "$tool (arkade get) already installed"
      fi
    else
      if [[ "$UPDATE" == "true" ]]; then
        skip "$tool (arkade get) is not installed"
      else
        PENDING_ARKADE_TOOLS+=("$tool"$'\t'"$install_args")
        PENDING_ARKADE_LABELS+=("$tool")
      fi
    fi
  done
}

build_arkade_command() {
  local command="arkade get"
  local entry tool install_args

  for entry in "${PENDING_ARKADE_TOOLS[@]:-}"; do
    IFS=$'\t' read -r tool install_args <<<"$entry"
    command+=" $tool"
    if [[ -n "$install_args" ]]; then
      command+=" $install_args"
    fi
  done
  command+=" --parallel 10"

  printf '%s\n' "$command"
}

run_arkade_batch() {
  if ! command_exists "arkade"; then
    return 0
  fi

  queue_arkade_tools
  if [[ ${#PENDING_ARKADE_TOOLS[@]} -eq 0 ]]; then
    return 0
  fi

  local arkade_command
  local action_word="Installing"
  local change_word="Installed"

  if [[ "$UPDATE" == "true" ]]; then
    action_word="Refreshing"
    change_word="Refreshed"
  fi

  arkade_command=$(build_arkade_command)

  info "$action_word ${#PENDING_ARKADE_TOOLS[@]} arkade tool(s)..."
  if is_dry_run; then
    info "Would execute: ${arkade_command% }"
    return 0
  fi

  run_eval_and_capture "${arkade_command% }"
  if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
    error "arkade batch command failed"
    return "$CAPTURE_EXIT_CODE"
  fi

  if [[ "$UPDATE" == "true" ]]; then
    info "$change_word ${#PENDING_ARKADE_TOOLS[@]} arkade tool(s)"
  else
    change "$change_word ${#PENDING_ARKADE_TOOLS[@]} arkade tool(s)"
  fi
}

run_code_extensions() {
  local vscode_cli
  local -a install_ids=()
  local line
  local tool manager type check_command extension_id install_args

  if ! get_vscode_cli >/dev/null 2>&1; then
    local has_code=false
    for line in "${METADATA_LINES[@]:-}"; do
      IFS=$'\t' read -r _ manager _ _ _ _ _ _ _ _ _ _ <<<"$line"
      if [[ "$manager" == "code" ]]; then
        has_code=true
        break
      fi
    done
    if [[ "$has_code" == "true" ]]; then
      skip "VSCode CLI unavailable; skipping extension management"
    fi
    return 0
  fi

  vscode_cli=$(get_vscode_cli)

  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool manager type check_command _ _ _ _ _ _ _ _ <<<"$line"
    if [[ "$manager" != "code" || "$type" != "extension" ]]; then
      continue
    fi

    extension_id=$(metadata_line_extension_id "$line")
    install_args=$(metadata_line_install_args "$line")

    if [[ -z "$extension_id" ]]; then
      skip "$tool (code extension) has no extension_id"
      continue
    fi

    if ! check_dependencies "$tool"; then
      continue
    fi

    if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
      if [[ "$UPDATE" == "true" ]]; then
        install_ids+=("$extension_id"$'\t'"$install_args")
      else
        skip "$tool (code extension) already installed"
      fi
    else
      if [[ "$UPDATE" == "true" ]]; then
        skip "$tool (code extension) is not installed"
      else
        install_ids+=("$extension_id"$'\t'"$install_args")
      fi
    fi
  done

  if [[ ${#install_ids[@]} -eq 0 ]]; then
    return 0
  fi

  local command="$vscode_cli"
  local entry extension_id entry_args
  for entry in "${install_ids[@]}"; do
    IFS=$'\t' read -r extension_id entry_args <<<"$entry"
    command+=" --install-extension $extension_id"
    if [[ -n "$entry_args" ]]; then
      command+=" $entry_args"
    fi
  done

  if is_dry_run; then
    info "Would execute: $command"
    return 0
  fi

  run_eval_and_capture "$command"
  if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
    error "VSCode extension install failed"
    return "$CAPTURE_EXIT_CODE"
  fi

  if [[ "$UPDATE" == "true" ]]; then
    change "Refreshed ${#install_ids[@]} VSCode extension(s)"
  else
    change "Installed ${#install_ids[@]} VSCode extension(s)"
  fi
}

run_manual_messages() {
  local line
  local tool manager type check_command skip_update description documentation_url

  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool manager type check_command skip_update _ _ _ description documentation_url _ _ <<<"$line"
    if [[ "$manager" != "manual" ]]; then
      continue
    fi

    if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" ""; then
      if [[ "$UPDATE" == "true" ]]; then
        skip "$tool (manual) update managed outside install.sh"
      else
        skip "$tool (manual) already present"
      fi
      continue
    fi

    if [[ "$UPDATE" == "true" ]]; then
      skip "$tool (manual) is not installed"
      continue
    fi

    info "$tool requires manual installation"
    [[ -n "$description" && "$description" != "null" ]] && info "  $description"
    [[ -n "$documentation_url" && "$documentation_url" != "null" ]] && info "  Download from: $documentation_url"
  done
}

run_direct_tool_command() {
  local command=$1

  if is_dry_run; then
    info "Would execute: $command"
    return 0
  fi

  run_eval_and_capture "$command"
  return "$CAPTURE_EXIT_CODE"
}

run_direct_metadata_tools() {
  local line
  local tool manager type check_command skip_update install_args apt_package extension_id app_id
  local -a apt_install_packages=()
  local -a apt_update_packages=()
  local -a cargo_update_tools=()
  local cargo_update_count=0

  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool manager type check_command skip_update _ extension_id app_id _ _ _ _ <<<"$line"
    install_args=$(metadata_line_install_args "$line")

    case "$manager" in
    apt)
      if [[ "$type" != "package" ]]; then
        skip "$tool (apt $type) not supported"
        continue
      fi

      if ! check_dependencies "$tool"; then
        continue
      fi

      apt_package=$(metadata_line_apt_package "$line")
      [[ -z "$apt_package" ]] && apt_package="$tool"

      if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
        if [[ "$UPDATE" == "true" ]]; then
          if [[ "$skip_update" == "true" ]]; then
            skip "$tool (apt package) update disabled by configuration"
          else
            apt_update_packages+=("$apt_package")
          fi
        else
          skip "$tool (apt package) already installed"
        fi
      else
        if [[ "$UPDATE" == "true" ]]; then
          skip "$tool (apt package) is not installed"
        else
          apt_install_packages+=("$apt_package")
        fi
      fi
      ;;
    cargo)
      if ! command_exists "cargo"; then
        skip "$tool (cargo $type) skipped because cargo is unavailable"
        continue
      fi

      if ! check_dependencies "$tool"; then
        continue
      fi

      if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
        if [[ "$UPDATE" == "true" ]]; then
          if [[ "$skip_update" == "true" ]]; then
            skip "$tool (cargo $type) update disabled by configuration"
          else
            cargo_update_tools+=("$tool")
          fi
        else
          skip "$tool (cargo $type) already installed"
        fi
      else
        if [[ "$UPDATE" == "true" ]]; then
          skip "$tool (cargo $type) is not installed"
        else
          if [[ "$type" == "git" ]]; then
            if ! run_direct_tool_command "cargo install --git $install_args $tool"; then
              error "Failed to install $tool (cargo $type)"
              return 1
            fi
          else
            if ! run_direct_tool_command "cargo install $install_args $tool"; then
              error "Failed to install $tool (cargo $type)"
              return 1
            fi
          fi
          change "Installed $tool (cargo $type)"
        fi
      fi
      ;;
    uv)
      if ! command_exists "uv"; then
        skip "$tool (uv $type) skipped because uv is unavailable"
        continue
      fi

      if ! check_dependencies "$tool"; then
        continue
      fi

      if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
        if [[ "$UPDATE" == "true" ]]; then
          if [[ "$skip_update" == "true" ]]; then
            skip "$tool (uv $type) update disabled by configuration"
          else
            if [[ "$FORCE" == "true" ]]; then
              if ! run_direct_tool_command "uv tool install --force $install_args $tool"; then
                error "Failed to update $tool (uv tool)"
                return 1
              fi
            else
              if ! run_direct_tool_command "uv tool install --upgrade $install_args $tool"; then
                error "Failed to update $tool (uv tool)"
                return 1
              fi
            fi
            change "Updated $tool (uv tool)"
          fi
        else
          skip "$tool (uv $type) already installed"
        fi
      else
        if [[ "$UPDATE" == "true" ]]; then
          skip "$tool (uv $type) is not installed"
        else
          if ! run_direct_tool_command "uv tool install $install_args $tool"; then
            error "Failed to install $tool (uv tool)"
            return 1
          fi
          change "Installed $tool (uv tool)"
        fi
      fi
      ;;
    mise)
      if ! command_exists "mise"; then
        skip "$tool (mise $type) skipped because mise is unavailable"
        continue
      fi

      if ! check_dependencies "$tool"; then
        continue
      fi

      if [[ "$UPDATE" == "true" ]]; then
        if [[ "$skip_update" == "true" ]]; then
          skip "$tool (mise $type) update disabled by configuration"
        else
          if ! run_direct_tool_command "mise upgrade $install_args $tool"; then
            error "Failed to update $tool (mise $type)"
            return 1
          fi
          change "Updated $tool (mise $type)"
        fi
      else
        if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
          skip "$tool (mise $type) already installed"
        else
          if ! run_direct_tool_command "mise install $install_args $tool"; then
            error "Failed to install $tool (mise $type)"
            return 1
          fi
          change "Installed $tool (mise $type)"
        fi
      fi
      ;;
    arkade)
      if [[ "$type" == "get" ]]; then
        continue
      fi

      if ! command_exists "arkade"; then
        skip "$tool (arkade $type) skipped because arkade is unavailable"
        continue
      fi

      if ! check_dependencies "$tool"; then
        continue
      fi

      if is_tool_installed_from_fields "$tool" "$manager" "$type" "$check_command" "$extension_id"; then
        if [[ "$UPDATE" == "true" ]]; then
          if [[ "$skip_update" == "true" ]]; then
            skip "$tool (arkade $type) update disabled by configuration"
          else
            skip "$tool (arkade $type) update not supported"
          fi
        else
          skip "$tool (arkade $type) already installed"
        fi
      else
        if [[ "$UPDATE" == "true" ]]; then
          skip "$tool (arkade $type) is not installed"
        else
          if [[ "$type" == "system" ]]; then
            if ! run_direct_tool_command "arkade system install $tool $install_args"; then
              error "Failed to install $tool (arkade $type)"
              return 1
            fi
          elif [[ "$type" == "install" ]]; then
            if ! run_direct_tool_command "arkade install $tool $install_args"; then
              error "Failed to install $tool (arkade $type)"
              return 1
            fi
          else
            skip "$tool (arkade $type) not supported"
            continue
          fi
          change "Installed $tool (arkade $type)"
        fi
      fi
      ;;
    brew | mas | code | manual)
      ;;
    *)
      if [[ -n "$manager" ]]; then
        skip "$tool ($manager $type) skipped because this manager is unsupported by install.sh"
      fi
      ;;
    esac
  done

  if [[ ${#apt_install_packages[@]} -gt 0 ]]; then
    run_apt_package_batch "install" "${apt_install_packages[@]}" || return 1
  fi

  if [[ ${#apt_update_packages[@]} -gt 0 ]]; then
    run_apt_package_batch "update" "${apt_update_packages[@]}" || return 1
  fi

  if [[ ${#cargo_update_tools[@]} -gt 0 ]]; then
    if is_dry_run; then
      info "Would execute: cargo install-update $(join_by_space "${cargo_update_tools[@]}")"
    elif cargo install-update --version >/dev/null 2>&1; then
      local cargo_list_output
      cargo_list_output=$(cargo install-update -l "${cargo_update_tools[@]}" 2>/dev/null || true)
      cargo_update_count=$(printf '%s\n' "$cargo_list_output" | awk 'NR > 1 && NF > 0 && $1 != "Package" && $1 !~ /^-+$/ { count++ } END { print count + 0 }')

      if [[ $cargo_update_count -eq 0 ]]; then
        skip "Selected cargo tools already up to date"
        return 0
      fi

      run_and_capture cargo install-update "${cargo_update_tools[@]}"
      if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
        error "cargo install-update failed"
        return "$CAPTURE_EXIT_CODE"
      fi
      change "Updated ${cargo_update_count} cargo tool(s)"
    else
      skip "cargo-update is not installed; skipping cargo binary updates"
    fi
  fi
}

run_brew_fallback_if_needed() {
  if command_exists "brew"; then
    return 0
  fi

  collect_brew_fallback_packages

  if [[ "$UPDATE" == "true" ]]; then
    if [[ ${#BREW_FALLBACK_UPDATE_PACKAGES[@]} -gt 0 ]]; then
      run_apt_package_batch "update" "${BREW_FALLBACK_UPDATE_PACKAGES[@]}" || return 1
    fi
  else
    if [[ ${#BREW_FALLBACK_INSTALL_PACKAGES[@]} -gt 0 ]]; then
      run_apt_package_batch "install" "${BREW_FALLBACK_INSTALL_PACKAGES[@]}" || return 1
    fi
  fi

  local line
  local tool manager type
  for line in "${METADATA_LINES[@]:-}"; do
    IFS=$'\t' read -r tool manager type _ _ _ _ _ _ _ _ _ <<<"$line"
    if [[ "$manager" == "brew" && "$type" != "package" ]]; then
      skip "$tool (brew $type) skipped because Homebrew is unavailable"
    fi
  done
}

run_mise_update() {
  if [[ "$UPDATE" != "true" ]]; then
    return 0
  fi

  if [[ ! -f "$INSTALL_REPO_ROOT/mise.toml" ]]; then
    return 0
  fi

  if ! command_exists "mise"; then
    skip "mise.toml present but mise is unavailable"
    return 0
  fi

  local outdated_json
  local outdated_count
  local outdated_output_file
  local outdated_exit_code
  local started_at
  local elapsed

  info "Checking runtimes declared in mise.toml for updates..."
  started_at=$(timestamp_now)
  outdated_output_file=$(mktemp)
  set +e
  mise outdated --json --local >"$outdated_output_file" 2>&1
  outdated_exit_code=$?
  set -e
  outdated_json=$(cat "$outdated_output_file")
  rm -f "$outdated_output_file"
  elapsed=$(duration_since "$started_at")

  print_captured_output "$outdated_json" "$outdated_exit_code"
  if [[ $outdated_exit_code -ne 0 ]]; then
    error "mise outdated failed"
    return "$outdated_exit_code"
  fi

  outdated_json=${outdated_json:-{}}
  if ! printf '%s' "$outdated_json" | grep -q '"[^"]\+"' ; then
    skip "Runtimes declared in mise.toml already up to date (checked in $elapsed)"
    return 0
  fi

  outdated_count=$(printf '%s\n' "$outdated_json" | yq -r 'keys | length' - 2>/dev/null)
  if [[ -z "$outdated_count" || "$outdated_count" == "null" ]]; then
    outdated_count=0
  fi

  if is_dry_run; then
    info "Would execute: mise upgrade --local"
    return 0
  fi

  info "Updating $(counted_noun "$outdated_count" "runtime") declared in mise.toml..."
  started_at=$(timestamp_now)
  run_and_capture mise upgrade --local
  if [[ $CAPTURE_EXIT_CODE -ne 0 ]]; then
    error "mise upgrade failed"
    return "$CAPTURE_EXIT_CODE"
  fi
  elapsed=$(duration_since "$started_at")

  change "Updated $(counted_noun "$outdated_count" "runtime") declared in mise.toml in $elapsed"
}

refresh_available_managers() {
  AVAILABLE_MANAGERS=()
  if [[ -f "$MANIFEST_METADATA" ]]; then
    while IFS= read -r manager; do
      [[ -n "$manager" ]] && AVAILABLE_MANAGERS+=("$manager")
    done < <(get_available_managers "$MANIFEST_METADATA")
  fi
}

clear_zsh_cache_if_needed() {
  if [[ "$UPDATE" != "true" || "$DRY_RUN" == "true" ]]; then
    return 0
  fi

  local zsh_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-init"
  if [[ -d "$zsh_cache_dir" ]]; then
    rm -rf "$zsh_cache_dir"
    change "Cleared zsh init cache"
  fi
}

print_selected_configs() {
  local config_file
  if [[ ${#RESOLVED_CONFIG_FILES[@]} -eq 0 ]]; then
    return 0
  fi

  info "Using configuration files:"
  for config_file in "${RESOLVED_CONFIG_FILES[@]}"; do
    info "  - $config_file"
  done
}

main() {
  [[ -z "$CONFIG_DIR" ]] && CONFIG_DIR="$DEFAULT_CONFIG_DIR"
  [[ "$DRY_RUN" == "true" ]] && info "Running in dry-run mode - no changes will be made"
  [[ "$FORCE" == "true" ]] && info "Running in force mode - destructive update/install paths will be retried where supported"

  if ! check_requirements; then
    return 1
  fi

  if ! prepare_config_files; then
    if [[ "$STOW" == "true" && ${#CONFIG_FILES[@]} -eq 0 ]]; then
      info "No configuration files specified - proceeding with stow only"
      RESOLVED_CONFIG_FILES=()
    else
      return 1
    fi
  fi

  print_selected_configs

  if [[ ${#RESOLVED_CONFIG_FILES[@]} -gt 0 ]]; then
    generate_manifests || return 1
    load_metadata_manifest
    load_arkade_manifest
    refresh_available_managers

    if [[ ${#AVAILABLE_MANAGERS[@]} -gt 0 ]]; then
      info "Available package managers: ${AVAILABLE_MANAGERS[*]}"
    else
      info "No package managers available - package operations will be skipped"
    fi

    if [[ "$UPDATE" == "true" ]]; then
      run_brew_update || return 1
      run_mas_update || return 1
      run_brew_fallback_if_needed || return 1
      run_direct_metadata_tools || return 1
      run_arkade_batch || return 1
      run_code_extensions || return 1
      run_manual_messages || return 1
      run_mise_update || return 1
      clear_zsh_cache_if_needed
    else
      run_brew_install || return 1
      run_brew_fallback_if_needed || return 1
      run_direct_metadata_tools || return 1
      run_arkade_batch || return 1
      run_code_extensions || return 1
      run_manual_messages || return 1
    fi
  fi

  if [[ "$STOW" == "true" ]]; then
    info "Running stow..."
    run_stow || return 1
  fi

  cleanup_generated_manifests
  return 0
}
