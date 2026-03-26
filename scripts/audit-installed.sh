#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$ROOT_DIR/_configs}"
OUT_BASE="${OUT_BASE:-$ROOT_DIR/_audit/installed}"

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/audit-installed.sh [options]

Compare installed brew/npm artifacts against the repo's YAML tool definitions.

Options:
  -C, --config-dir <path>  Config directory to scan (default: _configs)
  -h, --help               Show this help message
  -o, --out-base <path>    Base directory for timestamped audit output

Examples:
  scripts/audit-installed.sh
  scripts/audit-installed.sh --config-dir ./_configs --out-base /tmp/n-dotfiles-audit
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

count_lines() {
  wc -l <"$1" | tr -d ' '
}

normalize_tap() {
  local token="${1,,}"
  local part1
  local part2

  IFS='/' read -r part1 part2 _ <<<"$token"
  if [[ -n "$part1" && -n "$part2" ]]; then
    printf '%s/%s\n' "$part1" "$part2"
  fi
}

add_brew_artifact_from_token() {
  local token="$1"
  local out_file="$2"

  [[ -z "$token" || "$token" == -* ]] && return 0
  token="${token## }"
  token="${token%% }"
  if [[ "$token" == *"/"* ]]; then
    printf '%s\n' "${token##*/}" >>"$out_file"
  else
    printf '%s\n' "$token" >>"$out_file"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -C|--config-dir)
        if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
          CONFIG_DIR="$2"
          shift 2
        else
          error "--config-dir requires a path"
          usage 1
        fi
        ;;
      -o|--out-base)
        if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
          OUT_BASE="$2"
          shift 2
        else
          error "--out-base requires a path"
          usage 1
        fi
        ;;
      -h|--help)
        usage 0
        ;;
      *)
        error "Unknown option: $1"
        usage 1
        ;;
    esac
  done
}

main() {
  local stamp
  local out_dir
  local latest_link
  local expected_brew_formulae_raw
  local expected_brew_casks_raw
  local expected_brew_taps_raw
  local expected_npm_raw
  local npm_root

  parse_args "$@"

  if [[ ! -d "$CONFIG_DIR" ]]; then
    error "Config directory not found: $CONFIG_DIR"
    exit 1
  fi

  stamp="$(date +"%Y%m%d-%H%M%S")"
  out_dir="$OUT_BASE/$stamp"
  latest_link="$OUT_BASE/latest"

  mkdir -p "$out_dir"
  require_command yq

  expected_brew_formulae_raw="$out_dir/.expected_brew_formulae.raw"
  expected_brew_casks_raw="$out_dir/.expected_brew_casks.raw"
  expected_brew_taps_raw="$out_dir/.expected_brew_taps.raw"
  expected_npm_raw="$out_dir/.expected_npm.raw"

  : >"$expected_brew_formulae_raw"
  : >"$expected_brew_casks_raw"
  : >"$expected_brew_taps_raw"
  : >"$expected_npm_raw"

  while IFS= read -r yaml_file; do
    while IFS=$'\t' read -r tool manager type install_args; do
      [[ -z "${manager:-}" || "${manager:-}" == "null" ]] && continue

      case "$manager" in
        brew)
          case "$type" in
            tap)
              normalize_tap "$tool" >>"$expected_brew_taps_raw" || true
              for arg in $install_args; do
                normalize_tap "$arg" >>"$expected_brew_taps_raw" || true
              done
              ;;
            cask)
              add_brew_artifact_from_token "$tool" "$expected_brew_casks_raw"
              for arg in $install_args; do
                add_brew_artifact_from_token "$arg" "$expected_brew_casks_raw"
                normalize_tap "$arg" >>"$expected_brew_taps_raw" || true
              done
              ;;
            package|binary)
              add_brew_artifact_from_token "$tool" "$expected_brew_formulae_raw"
              for arg in $install_args; do
                add_brew_artifact_from_token "$arg" "$expected_brew_formulae_raw"
                normalize_tap "$arg" >>"$expected_brew_taps_raw" || true
              done
              ;;
            *)
              add_brew_artifact_from_token "$tool" "$expected_brew_formulae_raw"
              ;;
          esac
          ;;
        npm)
          add_brew_artifact_from_token "$tool" "$expected_npm_raw"
          for arg in $install_args; do
            add_brew_artifact_from_token "$arg" "$expected_npm_raw"
          done
          ;;
      esac
    done < <(yq -r '.tools // {} | to_entries[] | [.key, (.value.manager // ""), (.value.type // ""), ((.value.install_args // []) | join(" "))] | @tsv' "$yaml_file" 2>/dev/null || true)
  done < <(find "$CONFIG_DIR" -type f -name '*.yaml' | sort)

  sort -u "$expected_brew_formulae_raw" | sed '/^$/d' >"$out_dir/expected-brew-formulae.txt"
  sort -u "$expected_brew_casks_raw" | sed '/^$/d' >"$out_dir/expected-brew-casks.txt"
  sort -u "$expected_brew_taps_raw" | sed '/^$/d' >"$out_dir/expected-brew-taps.txt"
  sort -u "$expected_npm_raw" | sed '/^$/d' >"$out_dir/expected-npm-global.txt"

  if command -v brew >/dev/null 2>&1; then
    brew list --formula 2>/dev/null | sort -u >"$out_dir/installed-brew-formulae.txt"
    brew list --cask 2>/dev/null | sort -u >"$out_dir/installed-brew-casks.txt"
    brew tap 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u >"$out_dir/installed-brew-taps.txt"
  else
    : >"$out_dir/installed-brew-formulae.txt"
    : >"$out_dir/installed-brew-casks.txt"
    : >"$out_dir/installed-brew-taps.txt"
  fi

  if command -v npm >/dev/null 2>&1; then
    npm_root="$(npm root -g 2>/dev/null || true)"
    if [[ -n "$npm_root" ]]; then
      npm ls -g --depth=0 --parseable 2>/dev/null | sed '1d' | sed "s|^$npm_root/||" | sed '/^$/d' | sort -u >"$out_dir/installed-npm-global.txt" || true
    else
      : >"$out_dir/installed-npm-global.txt"
    fi
  else
    : >"$out_dir/installed-npm-global.txt"
  fi

  comm -23 "$out_dir/installed-brew-formulae.txt" "$out_dir/expected-brew-formulae.txt" >"$out_dir/unmanaged-brew-formulae.txt"
  comm -23 "$out_dir/installed-brew-casks.txt" "$out_dir/expected-brew-casks.txt" >"$out_dir/unmanaged-brew-casks.txt"
  comm -23 "$out_dir/installed-brew-taps.txt" "$out_dir/expected-brew-taps.txt" >"$out_dir/unmanaged-brew-taps.txt"
  comm -23 "$out_dir/installed-npm-global.txt" "$out_dir/expected-npm-global.txt" >"$out_dir/unmanaged-npm-global.txt"

  comm -12 "$out_dir/installed-brew-formulae.txt" "$out_dir/expected-brew-formulae.txt" >"$out_dir/managed-brew-formulae-installed.txt"
  comm -12 "$out_dir/installed-brew-casks.txt" "$out_dir/expected-brew-casks.txt" >"$out_dir/managed-brew-casks-installed.txt"
  comm -12 "$out_dir/installed-brew-taps.txt" "$out_dir/expected-brew-taps.txt" >"$out_dir/managed-brew-taps-installed.txt"
  comm -12 "$out_dir/installed-npm-global.txt" "$out_dir/expected-npm-global.txt" >"$out_dir/managed-npm-global-installed.txt"

  {
    echo "Audit timestamp: $stamp"
    echo "Output directory: $out_dir"
    echo ""
    echo "Installed counts"
    echo "  Brew formulae: $(count_lines "$out_dir/installed-brew-formulae.txt")"
    echo "  Brew casks:    $(count_lines "$out_dir/installed-brew-casks.txt")"
    echo "  Brew taps:     $(count_lines "$out_dir/installed-brew-taps.txt")"
    echo "  npm globals:   $(count_lines "$out_dir/installed-npm-global.txt")"
    echo ""
    echo "Unmanaged counts (installed but not in YAML manager entries)"
    echo "  Brew formulae: $(count_lines "$out_dir/unmanaged-brew-formulae.txt")"
    echo "  Brew casks:    $(count_lines "$out_dir/unmanaged-brew-casks.txt")"
    echo "  Brew taps:     $(count_lines "$out_dir/unmanaged-brew-taps.txt")"
    echo "  npm globals:   $(count_lines "$out_dir/unmanaged-npm-global.txt")"
    echo ""
    echo "Top unmanaged brew casks (first 20):"
    sed -n '1,20p' "$out_dir/unmanaged-brew-casks.txt"
    echo ""
    echo "Top unmanaged brew formulae (first 20):"
    sed -n '1,20p' "$out_dir/unmanaged-brew-formulae.txt"
    echo ""
    echo "Top unmanaged npm globals (first 20):"
    sed -n '1,20p' "$out_dir/unmanaged-npm-global.txt"
  } >"$out_dir/summary.txt"

  mkdir -p "$OUT_BASE"
  ln -sfn "$out_dir" "$latest_link"

  cat "$out_dir/summary.txt"
  echo ""
  echo "Detailed files:"
  echo "  $out_dir/unmanaged-brew-casks.txt"
  echo "  $out_dir/unmanaged-brew-formulae.txt"
  echo "  $out_dir/unmanaged-brew-taps.txt"
  echo "  $out_dir/unmanaged-npm-global.txt"
}

main "$@"
