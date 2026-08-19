#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/brew-bundle-install.sh <Brewfile>

Installs missing Brewfile entries without upgrading formulae or casks that
Homebrew already manages. Use `make update` to update installed entries.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -ne 1 ]]; then
  usage >&2
  exit 2
fi

brewfile=$1
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
brew_with_policy="$script_dir/brew-with-policy.sh"

declared_casks=$("$brew_with_policy" bundle list --cask --file="$brewfile")
installed_casks=$("$brew_with_policy" list --cask)
cask_skip="${HOMEBREW_BUNDLE_CASK_SKIP:-}"
declared_formulae=$("$brew_with_policy" bundle list --formula --file="$brewfile")
installed_formulae=$("$brew_with_policy" list --formula)
formula_skip="${HOMEBREW_BUNDLE_BREW_SKIP:-}"

for cask in $declared_casks; do
  case $'\n'"$installed_casks"$'\n' in
    *$'\n'"$cask"$'\n'*)
      printf 'Using %s (installed)\n' "$cask"
      cask_skip="${cask_skip:+$cask_skip }$cask"
      ;;
  esac
done

for formula in $declared_formulae; do
  formula_name=${formula##*/}
  case $'\n'"$installed_formulae"$'\n' in
    *$'\n'"$formula_name"$'\n'*)
      printf 'Using %s (installed)\n' "$formula"
      formula_skip="${formula_skip:+$formula_skip }$formula"
      ;;
  esac
done

export HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip"
export HOMEBREW_BUNDLE_BREW_SKIP="$formula_skip"
exec "$brew_with_policy" bundle install --no-upgrade --file="$brewfile"
