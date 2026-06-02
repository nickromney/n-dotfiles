#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/brew-update.sh <package-manager|update-all>

Runs the repository's Homebrew update sequence for a Makefile update context.

Contexts:
  package-manager  Required Homebrew update for `make brew update`
  update-all        Optional Homebrew update for `make update-all`

Examples:
  scripts/brew-update.sh package-manager
  scripts/brew-update.sh update-all
EOF
}

print_color() {
  printf "%b\n" "$1"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
brew_with_policy="${script_dir}/brew-with-policy.sh"

green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
red='\033[0;31m'
nc='\033[0m'

context="${1:-}"
case "$context" in
  package-manager)
    require_brew=true
    heading="Updating Homebrew packages and casks..."
    cask_warning="  Warning: brew upgrade --cask failed"
    success="\342\234\223 Homebrew updated"
    trailing_blank=false
    ;;
  update-all)
    require_brew=false
    heading="Updating Homebrew..."
    cask_warning="  Warning: brew cask upgrade failed (some casks may have issues)"
    success="\342\234\223 Homebrew update completed"
    trailing_blank=true
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if ! command -v brew >/dev/null 2>&1; then
  if [[ "$require_brew" == "true" ]]; then
    print_color "${red}Homebrew is not installed${nc}"
    exit 1
  fi
  exit 0
fi

print_color "${blue}${heading}${nc}"
"$brew_with_policy" update || print_color "${yellow}  Warning: brew update failed${nc}"
"$brew_with_policy" upgrade || print_color "${yellow}  Warning: brew upgrade failed${nc}"
"$brew_with_policy" upgrade --cask || print_color "${yellow}${cask_warning}${nc}"
"$brew_with_policy" cleanup || print_color "${yellow}  Warning: brew cleanup failed${nc}"
print_color "${green}${success}${nc}"

if [[ "$trailing_blank" == "true" ]]; then
  echo ""
fi
