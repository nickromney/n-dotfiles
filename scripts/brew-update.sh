#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/brew-update.sh <package-manager|update-all> [--dry-run|--no-input]

Runs the repository's Homebrew update sequence for a Makefile update context.

Options:
  --dry-run   Preview upgrades without changing machine state
  --no-input  Upgrade without prompting

Interactive upgrades default to yes. Running cask apps are not quit automatically.

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
brew_trust="${script_dir}/brew-trust.sh"

green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
red='\033[0;31m'
nc='\033[0m'

context="${1:-}"
case "$context" in
  package-manager)
    require_brew=true
    heading="Updating installed Homebrew formulae and casks..."
    success="\342\234\223 Homebrew updated"
    trailing_blank=false
    ;;
  update-all)
    require_brew=false
    heading="Updating installed Homebrew formulae and casks..."
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

shift
dry_run=false
no_input=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --no-input) no_input=true ;;
    *) usage >&2; exit 2 ;;
  esac
done

upgrade_packages() {
  local answer
  HOMEBREW_NO_AUTO_UPDATE=1 "$brew_with_policy" upgrade "$@" --dry-run || return
  if [[ "$dry_run" == "true" ]]; then
    return 0
  fi
  if [[ "$no_input" != "true" ]]; then
    while true; do
      printf 'Do you want to proceed with the upgrade? [Y/n] '
      if ! IFS= read -r answer; then
        printf '\nSkipping upgrade: no input. Use --no-input to approve unattended upgrades.\n'
        return 0
      fi
      case "$answer" in
        "" | y | Y | yes | YES) break ;;
        n | N | no | NO) return 0 ;;
        *) printf 'Please answer yes or no.\n' ;;
      esac
    done
  fi
  "$brew_with_policy" upgrade "$@" --yes
}

if ! command -v brew >/dev/null 2>&1; then
  if [[ "$require_brew" == "true" ]]; then
    print_color "${red}Homebrew is not installed${nc}"
    exit 1
  fi
  exit 0
fi

print_color "${blue}${heading}${nc}"
if [[ "$dry_run" != "true" ]]; then
  "$brew_trust" || print_color "${yellow}  Warning: Homebrew trust setup failed${nc}"
  "$brew_with_policy" update || print_color "${yellow}  Warning: brew update failed${nc}"
fi
upgrade_packages --formula || print_color "${yellow}  Warning: brew formula upgrade failed${nc}"
upgrade_packages --cask --no-quit || print_color "${yellow}  Warning: brew cask upgrade failed${nc}"
if [[ "$dry_run" != "true" ]]; then
  "$brew_with_policy" cleanup || print_color "${yellow}  Warning: brew cleanup failed${nc}"
  print_color "${green}${success}${nc}"
fi

if [[ "$trailing_blank" == "true" ]]; then
  echo ""
fi
