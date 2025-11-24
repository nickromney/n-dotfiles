#!/usr/bin/env bash

# Setup Git configuration includes from 1Password
# This script retrieves work-specific Git configuration from 1Password
# Usage: ./setup-gitconfig-from-1password.sh [-d|--dry-run]

set -euo pipefail

# Default values
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}ℹ${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
success() { echo -e "${GREEN}✓${NC} $1"; }

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -d, --dry-run    Check 1Password items without downloading"
  echo "  -h, --help       Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                # Download and setup Git configuration"
  echo "  $0 --dry-run      # Check what would be downloaded"
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      error "Unknown option: $1"
      echo "Use -h or --help for usage information" >&2
      exit 1
      ;;
  esac
done

# Check if op is installed
if ! command -v op >/dev/null 2>&1; then
  error "1Password CLI (op) is not installed"
  error "Install with: brew install --cask 1password-cli"
  exit 1
fi

# Check if signed in to 1Password
if ! op account list >/dev/null 2>&1; then
  warning "Not signed in to 1Password. Attempting to sign in..."
  if ! eval "$(op signin)"; then
    error "Failed to sign in to 1Password"
    exit 1
  fi
fi

# Configuration
readonly VAULT="${VAULT:-Private}" # Vault name is now configurable, defaults to "Private"
readonly WORK_DIR="$HOME/Developer/work"
readonly GIT_CONFIG_FILE="$WORK_DIR/.gitconfig_include"
declare BACKUP_DIR
BACKUP_DIR="$WORK_DIR/backups/$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR

# Git config items to download from 1Password
# Format: "1password_item_name:local_filename"
declare -a GIT_CONFIGS=(
  "work .gitconfig_include:.gitconfig_include"
)

# Dry run mode - just check what's available
if [ "$DRY_RUN" = true ]; then
  echo
  echo "========================================="
  echo "Git Config Dry Run - Checking 1Password"
  echo "========================================="
  echo

  info "Checking for Git configuration items in 1Password..."

  available_items=()
  missing_items=()

  for config_mapping in "${GIT_CONFIGS[@]}"; do
    IFS=':' read -r op_name local_name <<<"$config_mapping"

    if op item get "$op_name" --vault="$VAULT" >/dev/null 2>&1; then
      available_items+=("$op_name → $local_name")
    else
      missing_items+=("$op_name → $local_name")
    fi
  done

  if [ ${#available_items[@]} -gt 0 ]; then
    success "Found in 1Password:"
    for item in "${available_items[@]}"; do
      echo "  ✓ $item"
    done
  fi

  if [ ${#missing_items[@]} -gt 0 ]; then
    echo
    warning "Not found in 1Password:"
    for item in "${missing_items[@]}"; do
      echo "  ✗ $item"
    done
    echo
    echo "To add missing items:"
    echo "  1. Open 1Password"
    echo "  2. Create new item → Secure Note"
    echo "  3. Name it exactly as shown above (before the →)"
    echo "  4. Paste your Git config content in the notes field"
    echo "  5. Save in the '$VAULT' vault"
  fi

  # Check includeIf directive
  echo
  info "Checking main .gitconfig for includeIf directive..."
  GITCONFIG="$HOME/.gitconfig"
  INCLUDE_PATTERN='includeIf "gitdir:~/Developer/work/"'

  if [ -f "$GITCONFIG" ]; then
    if grep -q "$INCLUDE_PATTERN" "$GITCONFIG"; then
      success "Found includeIf directive in .gitconfig"
    else
      warning "includeIf directive not found in .gitconfig"
      echo "  Will need to add includeIf section when running without --dry-run"
    fi
  else
    warning "Main .gitconfig not found at $GITCONFIG"
  fi

  echo
  success "Dry run complete! No files were modified."
  echo "Run without --dry-run to actually download and apply configurations."
  exit 0
fi

# Ensure work directory exists
if [ ! -d "$WORK_DIR" ]; then
  info "Creating work directory: $WORK_DIR"
  mkdir -p "$WORK_DIR"
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"
info "Created backup directory: $BACKUP_DIR"

# Backup existing file
backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "$BACKUP_DIR/$(basename "$file")"
    info "Backed up $(basename "$file")"
  fi
}

# Step 1: Backup existing Git config includes
info "Backing up existing Git config files..."
for config_mapping in "${GIT_CONFIGS[@]}"; do
  local_name="${config_mapping#*:}"
  backup_file "$WORK_DIR/$local_name"
done

# Step 2: Download Git configs from 1Password
info "Retrieving Git configurations from 1Password..."
failed_configs=()
successful_configs=()

for config_mapping in "${GIT_CONFIGS[@]}"; do
  IFS=':' read -r op_name local_name <<<"$config_mapping"

  info "Downloading '$op_name'..."

  # Try to get the config from 1Password Secure Note
  # Try notesPlain first (Secure Notes), then notes (older format)
  if op item get "$op_name" --vault="$VAULT" --fields notesPlain 2>/dev/null >"$WORK_DIR/$local_name" ||
     op item get "$op_name" --vault="$VAULT" --fields notes 2>/dev/null >"$WORK_DIR/$local_name"; then
    # Check if file has content
    if [ -s "$WORK_DIR/$local_name" ]; then
      # Remove surrounding quotes and fix escaped quotes (1Password CLI adds them)
      # First remove outer quotes from entire file, then fix doubled quotes
      sed -i '' 's/^"//; s/"$//; s/""/"/g' "$WORK_DIR/$local_name"
      chmod 644 "$WORK_DIR/$local_name"
      successful_configs+=("$local_name")

      # Verify it's valid Git config syntax
      if git config --file="$WORK_DIR/$local_name" --list >/dev/null 2>&1; then
        success "Downloaded and validated $local_name"
      else
        warning "$local_name downloaded but may have syntax issues"
      fi
    else
      failed_configs+=("$op_name → $local_name")
      rm -f "$WORK_DIR/$local_name" # Remove empty file if created
    fi
  else
    failed_configs+=("$op_name → $local_name")
    rm -f "$WORK_DIR/$local_name" # Remove empty file if created
  fi
done

# Step 3: Verify main .gitconfig has the includeIf directive
info "Checking main .gitconfig for includeIf directive..."
GITCONFIG="$HOME/.gitconfig"
INCLUDE_PATTERN='includeIf "gitdir:~/Developer/work/"'

if [ -f "$GITCONFIG" ]; then
  if grep -q "$INCLUDE_PATTERN" "$GITCONFIG"; then
    success "Found includeIf directive in .gitconfig"
  else
    warning "includeIf directive not found in .gitconfig"
    echo "  Add these lines to your ~/.gitconfig:"
    echo
    echo '  [includeIf "gitdir:~/Developer/work/"]'
    echo '    path = ~/Developer/work/.gitconfig_include'
    echo
  fi
else
  warning "Main .gitconfig not found at $GITCONFIG"
fi

# Step 4: Report results
echo
echo "========================================="
echo "Git Config Setup Summary"
echo "========================================="

if [ ${#successful_configs[@]} -gt 0 ]; then
  success "Successfully downloaded configs:"
  for config in "${successful_configs[@]}"; do
    echo "  • $config"
  done

  # Show what was configured
  if [ -f "$GIT_CONFIG_FILE" ]; then
    echo
    info "Configuration applied:"
    # Show URL rewrites
    git config --file="$GIT_CONFIG_FILE" --get-regexp "url\..*\.insteadof" 2>/dev/null | while read -r key value; do
      echo "  • URL rewrite: $value → ${key#url.}"
    done
    # Show user overrides
    if git config --file="$GIT_CONFIG_FILE" user.email >/dev/null 2>&1; then
      email=$(git config --file="$GIT_CONFIG_FILE" user.email)
      echo "  • Work email: $email"
    fi
  fi
fi

if [ ${#failed_configs[@]} -gt 0 ]; then
  echo
  warning "Failed to download configs:"
  for config in "${failed_configs[@]}"; do
    echo "  ✗ $config"
  done
  echo
  echo "To add Git config to 1Password:"
  echo "  1. Open 1Password"
  echo "  2. Create new item → Secure Note"
  echo "  3. Name it exactly as shown above (before the →)"
  echo "  4. Paste your Git config content in the notes field"
  echo "  5. Save in the '$VAULT' vault"
  echo
  echo "Example content for 'work .gitconfig_include':"
  echo '  [url "github-work-alias:OrgName/"]'
  echo '    insteadOf = git@github.com:OrgName/'
  echo '    insteadOf = https://github.com/OrgName/'
  echo '  [user]'
  echo '    email = first.last@company.com'
fi

# Step 5: Test Git configuration
echo
info "Testing Git configuration..."
echo "You can verify your work Git config with:"
echo "  cd ~/Developer/work/<any-repo>"
echo "  git config user.email  # Should show work email"
echo "  git remote -v          # Should use work SSH aliases"

echo
success "Git config setup complete!"
echo "Backups saved to: $BACKUP_DIR"
