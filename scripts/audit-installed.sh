#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$ROOT_DIR/_configs}"
OUT_BASE="${OUT_BASE:-$ROOT_DIR/_audit/installed}"
STAMP="$(date +"%Y%m%d-%H%M%S")"
OUT_DIR="$OUT_BASE/$STAMP"
LATEST_LINK="$OUT_BASE/latest"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  fi
}

count_lines() {
  wc -l <"$1" | tr -d ' '
}

normalize_tap() {
  local token="${1,,}"
  local part1 part2
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

mkdir -p "$OUT_DIR"
require_command yq

expected_brew_formulae_raw="$OUT_DIR/.expected_brew_formulae.raw"
expected_brew_casks_raw="$OUT_DIR/.expected_brew_casks.raw"
expected_brew_taps_raw="$OUT_DIR/.expected_brew_taps.raw"
expected_npm_raw="$OUT_DIR/.expected_npm.raw"

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

sort -u "$expected_brew_formulae_raw" | sed '/^$/d' >"$OUT_DIR/expected-brew-formulae.txt"
sort -u "$expected_brew_casks_raw" | sed '/^$/d' >"$OUT_DIR/expected-brew-casks.txt"
sort -u "$expected_brew_taps_raw" | sed '/^$/d' >"$OUT_DIR/expected-brew-taps.txt"
sort -u "$expected_npm_raw" | sed '/^$/d' >"$OUT_DIR/expected-npm-global.txt"

if command -v brew >/dev/null 2>&1; then
  brew list --formula 2>/dev/null | sort -u >"$OUT_DIR/installed-brew-formulae.txt"
  brew list --cask 2>/dev/null | sort -u >"$OUT_DIR/installed-brew-casks.txt"
  brew tap 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u >"$OUT_DIR/installed-brew-taps.txt"
else
  : >"$OUT_DIR/installed-brew-formulae.txt"
  : >"$OUT_DIR/installed-brew-casks.txt"
  : >"$OUT_DIR/installed-brew-taps.txt"
fi

if command -v npm >/dev/null 2>&1; then
  npm_root="$(npm root -g 2>/dev/null || true)"
  if [[ -n "$npm_root" ]]; then
    npm ls -g --depth=0 --parseable 2>/dev/null | sed '1d' | sed "s|^$npm_root/||" | sed '/^$/d' | sort -u >"$OUT_DIR/installed-npm-global.txt" || true
  else
    : >"$OUT_DIR/installed-npm-global.txt"
  fi
else
  : >"$OUT_DIR/installed-npm-global.txt"
fi

comm -23 "$OUT_DIR/installed-brew-formulae.txt" "$OUT_DIR/expected-brew-formulae.txt" >"$OUT_DIR/unmanaged-brew-formulae.txt"
comm -23 "$OUT_DIR/installed-brew-casks.txt" "$OUT_DIR/expected-brew-casks.txt" >"$OUT_DIR/unmanaged-brew-casks.txt"
comm -23 "$OUT_DIR/installed-brew-taps.txt" "$OUT_DIR/expected-brew-taps.txt" >"$OUT_DIR/unmanaged-brew-taps.txt"
comm -23 "$OUT_DIR/installed-npm-global.txt" "$OUT_DIR/expected-npm-global.txt" >"$OUT_DIR/unmanaged-npm-global.txt"

comm -12 "$OUT_DIR/installed-brew-formulae.txt" "$OUT_DIR/expected-brew-formulae.txt" >"$OUT_DIR/managed-brew-formulae-installed.txt"
comm -12 "$OUT_DIR/installed-brew-casks.txt" "$OUT_DIR/expected-brew-casks.txt" >"$OUT_DIR/managed-brew-casks-installed.txt"
comm -12 "$OUT_DIR/installed-brew-taps.txt" "$OUT_DIR/expected-brew-taps.txt" >"$OUT_DIR/managed-brew-taps-installed.txt"
comm -12 "$OUT_DIR/installed-npm-global.txt" "$OUT_DIR/expected-npm-global.txt" >"$OUT_DIR/managed-npm-global-installed.txt"

{
  echo "Audit timestamp: $STAMP"
  echo "Output directory: $OUT_DIR"
  echo ""
  echo "Installed counts"
  echo "  Brew formulae: $(count_lines "$OUT_DIR/installed-brew-formulae.txt")"
  echo "  Brew casks:    $(count_lines "$OUT_DIR/installed-brew-casks.txt")"
  echo "  Brew taps:     $(count_lines "$OUT_DIR/installed-brew-taps.txt")"
  echo "  npm globals:   $(count_lines "$OUT_DIR/installed-npm-global.txt")"
  echo ""
  echo "Unmanaged counts (installed but not in YAML manager entries)"
  echo "  Brew formulae: $(count_lines "$OUT_DIR/unmanaged-brew-formulae.txt")"
  echo "  Brew casks:    $(count_lines "$OUT_DIR/unmanaged-brew-casks.txt")"
  echo "  Brew taps:     $(count_lines "$OUT_DIR/unmanaged-brew-taps.txt")"
  echo "  npm globals:   $(count_lines "$OUT_DIR/unmanaged-npm-global.txt")"
  echo ""
  echo "Top unmanaged brew casks (first 20):"
  sed -n '1,20p' "$OUT_DIR/unmanaged-brew-casks.txt"
  echo ""
  echo "Top unmanaged brew formulae (first 20):"
  sed -n '1,20p' "$OUT_DIR/unmanaged-brew-formulae.txt"
  echo ""
  echo "Top unmanaged npm globals (first 20):"
  sed -n '1,20p' "$OUT_DIR/unmanaged-npm-global.txt"
} >"$OUT_DIR/summary.txt"

mkdir -p "$OUT_BASE"
ln -sfn "$OUT_DIR" "$LATEST_LINK"

cat "$OUT_DIR/summary.txt"
echo ""
echo "Detailed files:"
echo "  $OUT_DIR/unmanaged-brew-casks.txt"
echo "  $OUT_DIR/unmanaged-brew-formulae.txt"
echo "  $OUT_DIR/unmanaged-brew-taps.txt"
echo "  $OUT_DIR/unmanaged-npm-global.txt"
