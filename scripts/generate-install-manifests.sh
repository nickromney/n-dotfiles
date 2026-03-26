#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
OUTPUT_DIR="${OUTPUT_DIR:-}"
CONFIG_FILES=()

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/generate-install-manifests.sh [options]
Usage: scripts/generate-install-manifests.sh <output-dir> <config> [<config> ...]

Generate install manifests from one or more config bundles.

Options:
  -c, --config <name>      Add configuration file to include (repeatable)
  -d, --dry-run            Print the generated manifests instead of writing them
  -h, --help               Show this help message
  -o, --output-dir <path>  Output directory for generated manifests

Generates:
  - Brewfile
  - arkade.tsv
  - metadata.json

Examples:
  scripts/generate-install-manifests.sh -o _generated/manifests -c host/common -c host/personal
  scripts/generate-install-manifests.sh --dry-run -o /tmp/manifests -c shared/shell -c focus/kubernetes
  scripts/generate-install-manifests.sh /tmp/manifests shared/shell host/common
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Required command not found: $1"
    exit 1
  fi
}

resolve_config_file() {
  local config="$1"
  local candidate="$config"

  if [[ "$candidate" != *.yaml && "$candidate" != *.yml ]]; then
    candidate="${candidate}.yaml"
  fi

  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -f "$REPO_ROOT/_configs/$candidate" ]]; then
    printf '%s\n' "$REPO_ROOT/_configs/$candidate"
    return 0
  fi

  error "Could not find config: $config"
  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -c|--config)
        if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
          CONFIG_FILES+=("$2")
          shift 2
        else
          error "--config requires a configuration name"
          usage 1
        fi
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -o|--output-dir)
        if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
          OUTPUT_DIR="$2"
          shift 2
        else
          error "--output-dir requires a path"
          usage 1
        fi
        ;;
      -h|--help)
        usage 0
        ;;
      -*)
        error "Unknown option: $1"
        usage 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -gt 0 ]]; then
    if [[ -z "$OUTPUT_DIR" ]]; then
      OUTPUT_DIR="$1"
      shift
    fi
    while [[ $# -gt 0 ]]; do
      CONFIG_FILES+=("$1")
      shift
    done
  fi

  if [[ -z "$OUTPUT_DIR" ]]; then
    error "An output directory is required"
    usage 1
  fi

  if [[ ${#CONFIG_FILES[@]} -eq 0 ]]; then
    error "At least one config is required"
    usage 1
  fi
}

generate_arkade_manifest() {
  local output_file="$1"
  local arkade_tmp
  local config
  local cfg_file

  arkade_tmp="$(mktemp)"
  cleanup_files+=("$arkade_tmp")

  for config in "${CONFIG_FILES[@]}"; do
    cfg_file="$(resolve_config_file "$config")"
    yq -r '
      .tools // {} | to_entries[]
      | select(.value.manager == "arkade" and .value.type == "get")
      | .key + "\t" + ((.value.install_args // []) | join(" "))
    ' "$cfg_file" >>"$arkade_tmp"
  done

  sort -u "$arkade_tmp" | sed '/^[[:space:]]*$/d' >"$output_file"
}

generate_metadata_manifest() {
  local output_file="$1"
  local metadata_tmp
  local config
  local cfg_file

  metadata_tmp="$(mktemp)"
  cleanup_files+=("$metadata_tmp")

  for config in "${CONFIG_FILES[@]}"; do
    cfg_file="$(resolve_config_file "$config")"
    yq -o=json -I=0 '
      .tools // {} | to_entries[]
      | {
          "tool": .key,
          "manager": (.value.manager // ""),
          "type": (.value.type // ""),
          "check_command": (.value.check_command // ""),
          "install_args": (.value.install_args // []),
          "skip_update": (.value.skip_update // false),
          "apt_package": (.value.apt_package // null),
          "extension_id": (.value.extension_id // null),
          "app_id": (.value.app_id // null),
          "description": (.value.description // null),
          "documentation_url": (.value.documentation_url // null),
          "category": (.value.category // null),
          "dependencies": (.value.dependencies // [])
        }
    ' "$cfg_file" >>"$metadata_tmp"
  done

  {
    echo "["
    awk '
      NF && !seen[$0]++ {
        if (count > 0) {
          printf(",\n")
        }
        printf("%s", $0)
        count++
      }
      END {
        if (count > 0) {
          printf("\n")
        }
      }
    ' "$metadata_tmp"
    echo "]"
  } >"$output_file"
}

print_dry_run_preview() {
  local temp_dir="$1"

  echo "[dry-run] Would generate install manifests in $OUTPUT_DIR"
  echo
  echo "--- $OUTPUT_DIR/Brewfile ---"
  cat "$temp_dir/Brewfile"
  echo
  echo "--- $OUTPUT_DIR/arkade.tsv ---"
  cat "$temp_dir/arkade.tsv"
  echo
  echo "--- $OUTPUT_DIR/metadata.json ---"
  cat "$temp_dir/metadata.json"
}

cleanup() {
  local path
  for path in "${cleanup_files[@]:-}"; do
    rm -f "$path"
  done
  for path in "${cleanup_paths[@]:-}"; do
    if [[ -d "$path" ]]; then
      rm -rf "$path"
    else
      rm -f "$path"
    fi
  done
}

main() {
  local -a brewfile_args
  local working_dir

  parse_args "$@"
  require_command yq

  working_dir="$(mktemp -d)"
  cleanup_paths=("$working_dir")
  cleanup_files=()
  trap cleanup EXIT

  brewfile_args=(--output-file "$working_dir/Brewfile")
  for config in "${CONFIG_FILES[@]}"; do
    brewfile_args+=(--config "$config")
  done

  "$REPO_ROOT/scripts/generate-brewfile.sh" "${brewfile_args[@]}" >/dev/null
  generate_arkade_manifest "$working_dir/arkade.tsv"
  generate_metadata_manifest "$working_dir/metadata.json"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_dry_run_preview "$working_dir"
    return 0
  fi

  mkdir -p "$OUTPUT_DIR"
  cp "$working_dir/Brewfile" "$OUTPUT_DIR/Brewfile"
  cp "$working_dir/arkade.tsv" "$OUTPUT_DIR/arkade.tsv"
  cp "$working_dir/metadata.json" "$OUTPUT_DIR/metadata.json"
  printf 'Generated install manifests in %s\n' "$OUTPUT_DIR"
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cleanup_paths=()
cleanup_files=()

main "$@"
