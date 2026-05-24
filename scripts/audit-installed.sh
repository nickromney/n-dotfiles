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

Generated files include unmanaged package lists plus package-manager-surface.tsv,
which traces globally installed npm packages and Homebrew artifacts back to the
package manager that owns them, whether this repo manages them, and direct npm
dependency footprint where package metadata is local.
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

is_listed() {
  local needle="$1"
  local file="$2"

  grep -Fxq "$needle" "$file" 2>/dev/null
}

lookup_tsv_value() {
  local key="$1"
  local file="$2"

  awk -F '\t' -v key="$key" '$1 == key { print $2; found = 1; exit } END { if (!found) exit 1 }' "$file" 2>/dev/null || true
}

node_package_json_field() {
  local package_json="$1"
  local field="$2"

  node -e '
const fs = require("fs");
const path = process.argv[1];
const field = process.argv[2];
try {
  const data = JSON.parse(fs.readFileSync(path, "utf8"));
  process.stdout.write(data[field] || "");
} catch {
  process.exit(0);
}
' "$package_json" "$field"
}

node_package_dependency_count() {
  local package_json="$1"

  node -e '
const fs = require("fs");
const path = process.argv[1];
try {
  const data = JSON.parse(fs.readFileSync(path, "utf8"));
  const deps = new Set();
  for (const key of ["dependencies", "optionalDependencies", "peerDependencies"]) {
    for (const name of Object.keys(data[key] || {})) deps.add(name);
  }
  process.stdout.write(String(deps.size));
} catch {
  process.stdout.write("0");
}
' "$package_json"
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

write_brew_surface() {
  local out_dir="$1"
  local surface_file="$2"
  local leaves_file="$out_dir/installed-brew-leaves.txt"
  local formula
  local cask
  local version
  local managed
  local leaf

  : >"$leaves_file"

  if ! command -v brew >/dev/null 2>&1; then
    return 0
  fi

  brew leaves 2>/dev/null | sort -u >"$leaves_file" || : >"$leaves_file"

  while IFS= read -r formula; do
    [[ -z "$formula" ]] && continue

    version="$(lookup_tsv_value "$formula" "$out_dir/installed-brew-formulae-versions.tsv")"
    [[ -z "$version" ]] && version="unknown"

    managed="no"
    if is_listed "$formula" "$out_dir/expected-brew-formulae.txt"; then
      managed="yes"
    fi

    leaf="no"
    if is_listed "$formula" "$leaves_file"; then
      leaf="yes"
    fi

    printf 'brew\tformula\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$formula" "$version" "$managed" "$leaf" "n/a" "brew"
  done <"$out_dir/installed-brew-formulae.txt" >>"$surface_file"

  while IFS= read -r cask; do
    [[ -z "$cask" ]] && continue

    version="$(lookup_tsv_value "$cask" "$out_dir/installed-brew-cask-versions.tsv")"
    [[ -z "$version" ]] && version="unknown"

    managed="no"
    if is_listed "$cask" "$out_dir/expected-brew-casks.txt"; then
      managed="yes"
    fi

    printf 'brew\tcask\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$cask" "$version" "$managed" "n/a" "n/a" "brew"
  done <"$out_dir/installed-brew-casks.txt" >>"$surface_file"
}

write_npm_surface() {
  local out_dir="$1"
  local surface_file="$2"
  local npm_root="$3"
  local package
  local package_path
  local package_json
  local version
  local managed
  local dep_count

  if [[ -z "$npm_root" || ! -d "$npm_root" ]] || ! command -v node >/dev/null 2>&1; then
    return 0
  fi

  while IFS= read -r package; do
    [[ -z "$package" ]] && continue

    package_path="$npm_root/$package"
    package_json="$package_path/package.json"
    version="unknown"
    if [[ -f "$package_json" ]]; then
      version="$(node_package_json_field "$package_json" version)"
      [[ -z "$version" ]] && version="unknown"
    fi

    managed="no"
    if is_listed "$package" "$out_dir/expected-npm-global.txt"; then
      managed="yes"
    fi

    dep_count="0"
    if [[ -f "$package_json" ]]; then
      dep_count="$(node_package_dependency_count "$package_json")"
    fi

    printf 'npm\tglobal\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$package" "$version" "$managed" "direct" "$dep_count" "$package_path"
  done <"$out_dir/installed-npm-global.txt" >>"$surface_file"
}

write_package_manager_surface() {
  local out_dir="$1"
  local npm_root="$2"
  local surface_file="$out_dir/package-manager-surface.tsv"

  printf 'manager\tkind\tname\tversion\trepo_managed\trequested_or_leaf\tdependency_count\towner_path\n' >"$surface_file"
  write_brew_surface "$out_dir" "$surface_file"
  write_npm_surface "$out_dir" "$surface_file" "$npm_root"
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
    brew list --versions --formula 2>/dev/null | awk '{ name = $1; $1 = ""; sub(/^ /, ""); print name "\t" $0 }' | sort -u >"$out_dir/installed-brew-formulae-versions.tsv"
    brew list --versions --cask 2>/dev/null | awk '{ name = $1; $1 = ""; sub(/^ /, ""); print name "\t" $0 }' | sort -u >"$out_dir/installed-brew-cask-versions.tsv"
  else
    : >"$out_dir/installed-brew-formulae.txt"
    : >"$out_dir/installed-brew-casks.txt"
    : >"$out_dir/installed-brew-taps.txt"
    : >"$out_dir/installed-brew-formulae-versions.tsv"
    : >"$out_dir/installed-brew-cask-versions.tsv"
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

  write_package_manager_surface "$out_dir" "${npm_root:-}"

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
    echo ""
    echo "Largest npm global dependency footprints:"
    awk -F '\t' 'NR > 1 && $1 == "npm" { print $7 "\t" $3 }' "$out_dir/package-manager-surface.tsv" | sort -rn | sed -n '1,10p'
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
  echo "  $out_dir/package-manager-surface.tsv"
}

main "$@"
