#!/usr/bin/env bash

# Setup SSH config and keys from 1Password
# This script retrieves SSH configuration from 1Password
# By default, only public keys are downloaded (private keys stay in 1Password)
# Usage: ./setup-ssh-from-1password.sh [-d|--dry-run] [-u|--unsafe] [-p|--profile PROFILE]

set -euo pipefail

# Keep downloaded SSH material private from file creation time, before chmod runs.
umask 077

# Default values
DRY_RUN="${DRY_RUN:-false}"
UNSAFE_MODE="${UNSAFE_MODE:-false}"
MACHINE_PROFILE="${MACHINE_PROFILE:-}"
FORCE_OVERWRITE="${FORCE_OVERWRITE:-false}"
NO_INPUT="${NO_INPUT:-false}"
ASSUME_YES="${ASSUME_YES:-false}"
LITERAL_TILDE='~'
SSH_CONFIG_BASE_ITEM_NAME="${LITERAL_TILDE}/.ssh/config"

if [[ -n "${NON_INTERACTIVE:-}" ]]; then
  NO_INPUT=true
fi

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
  local exit_code=${1:-0}

  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -p, --profile PROFILE   Machine profile (personal, work-2024-client-1, work-2025-client-1, work-2025-client-2)"
  echo "  -d, --dry-run           Check 1Password items without downloading"
  echo "  -f, --force             Overwrite existing keys (default: skip existing)"
  echo "      --no-input          Disable prompts; require --profile and --yes for unsafe mode"
  echo "  -u, --unsafe            Download private keys (DANGEROUS - breaks 1Password SSH Agent model)"
  echo "  -y, --yes               Confirm unsafe private-key download without prompting"
  echo "  -h, --help              Show this help message"
  echo ""
  echo "Machine Profiles:"
  echo "  personal            - Personal GitHub keys (authentication + signing)"
  echo "  work-2024-client-1  - Work 2024 Client 1 AWS key"
  echo "  work-2025-client-1  - Work 2025 Client 1 GitHub key"
  echo "  work-2025-client-2  - Work 2025 Client 2 GitHub + Gitea + Azure DevOps keys"
  echo ""
  echo "Default behavior:"
  echo "  - Downloads base SSH config from 1Password"
  echo "  - Downloads a per-profile SSH config fragment from 1Password"
  echo "  - Downloads public keys only (private keys stay in 1Password)"
  echo "  - Uses 1Password SSH Agent for authentication"
  echo "  - Prompts for machine profile if not specified"
  echo "  - --no-input requires --profile and skips all prompts"
  echo "  - Skips existing keys (use --force to overwrite)"
  echo ""
  echo "Examples:"
  echo "  $0 --profile work-2025-client-2           # Download only Client 2 keys"
  echo "  $0 -p personal --dry-run                  # Check personal keys"
  echo "  $0 -p work-2025-client-1                  # Add Client 1 keys (keeps existing)"
  echo "  $0 -p personal --force                    # Refresh personal keys"
  echo "  $0 --profile personal --no-input         # Non-interactive safe mode"
  echo "  $0 --profile personal --unsafe --yes     # Non-interactive private key download"
  echo "  $0 --profile work-2025-client-2 --unsafe  # Download private keys (requires confirmation)"
  echo ""
  echo "Multi-profile workflow (consulting laptop):"
  echo "  $0 -p personal                            # Add personal keys"
  echo "  $0 -p work-2025-client-1                  # Add Client 1 keys"
  echo "  $0 -p work-2025-client-2                  # Add Client 2 keys"
  echo "  # Result: All three sets of keys on one machine"
  echo ""
  echo "WARNING: The --unsafe option defeats the purpose of 1Password SSH Agent!"
  echo "         Private keys should remain in 1Password for security."
  exit "$exit_code"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -p | --profile)
      if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
        MACHINE_PROFILE="$2"
        shift 2
      else
        error "--profile requires a machine profile"
        usage 1
      fi
      ;;
    -d | --dry-run)
      DRY_RUN=true
      shift
      ;;
    -f | --force)
      FORCE_OVERWRITE=true
      shift
      ;;
    -u | --unsafe)
      UNSAFE_MODE=true
      shift
      ;;
    --no-input)
      NO_INPUT=true
      shift
      ;;
    -y | --yes)
      ASSUME_YES=true
      shift
      ;;
    -h | --help)
      usage 0
      ;;
    *)
      error "Unknown option: $1"
      usage 1
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
readonly DEFAULT_VAULT="${VAULT:-Private}" # Backward-compatible default
readonly SSH_CONFIG_VAULT="${SSH_CONFIG_VAULT:-$DEFAULT_VAULT}"
readonly SSH_DIR="$HOME/.ssh"
readonly SSH_CONFIG_DIR="$SSH_DIR/config.d"
declare BACKUP_DIR
BACKUP_DIR="$SSH_DIR/backups/$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR

# Per-profile SSH config fragments
# Format: "profile:1password_item_name:local_filename:vault_name"
declare -a ALL_SSH_CONFIG_FRAGMENTS=(
  "personal:${LITERAL_TILDE}/.ssh/config.d/personal.conf:personal.conf:Private"
  "work-2024-client-1:${LITERAL_TILDE}/.ssh/config.d/work-2024-client-1.conf:work-2024-client-1.conf:Work 2024 Client 1"
  "work-2025-client-1:${LITERAL_TILDE}/.ssh/config.d/work-2025-client-1.conf:work-2025-client-1.conf:Work 2025 Client 1"
  "work-2025-client-2:${LITERAL_TILDE}/.ssh/config.d/work-2025-client-2.conf:work-2025-client-2.conf:Work 2025 Client 2"
)

# All available SSH keys in 1Password
# Format: "1password_item_name:local_filename:vault_name"
declare -a ALL_SSH_KEYS=(
  "personal_github_authentication:personal_github_authentication:Private"
  "personal_github_signing:personal_github_signing:Private"
  "work_2024_client_1_aws:work_2024_client_1_aws.pem:Work 2024 Client 1"
  "work_2025_client_1_github:work_2025_client_1_github:Work 2025 Client 1"
  "work_2025_client_2_github:work_2025_client_2_github:Work 2025 Client 2"
  "work_2025_client_2_gitea:work_2025_client_2_gitea:Work 2025 Client 2"
  "work_2025_client_2_ado:work_2025_client_2_ado:Work 2025 Client 2"
)

# Get keys for a given machine profile (bash 3.x compatible)
# This ensures least-privilege access and prevents credential leakage between clients
get_profile_keys() {
  local profile="$1"
  case "$profile" in
    personal)
      echo "personal_github_authentication personal_github_signing"
      ;;
    work-2024-client-1)
      echo "work_2024_client_1_aws"
      ;;
    work-2025-client-1)
      echo "work_2025_client_1_github"
      ;;
    work-2025-client-2)
      echo "work_2025_client_2_github work_2025_client_2_gitea work_2025_client_2_ado"
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

# Validate profile exists
is_valid_profile() {
  local profile="$1"
  case "$profile" in
    personal | work-2024-client-1 | work-2025-client-1 | work-2025-client-2)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Prompt for machine profile if not specified
if [[ -z "$MACHINE_PROFILE" ]]; then
  if [[ "$NO_INPUT" == "true" ]]; then
    error "No machine profile specified."
    echo "Re-run with: $0 --profile <personal|work-2024-client-1|work-2025-client-1|work-2025-client-2> --no-input" >&2
    exit 1
  fi

  echo
  warning "No machine profile specified. Please select your machine type:"
  echo
  echo "  1) personal            - Personal GitHub keys"
  echo "  2) work-2024-client-1  - Work 2024 Client 1 AWS key"
  echo "  3) work-2025-client-1  - Work 2025 Client 1 GitHub key"
  echo "  4) work-2025-client-2  - Work 2025 Client 2 GitHub + Gitea + Azure DevOps keys"
  echo
  read -r -p "Enter selection (1-4): " selection

  case $selection in
    1) MACHINE_PROFILE="personal" ;;
    2) MACHINE_PROFILE="work-2024-client-1" ;;
    3) MACHINE_PROFILE="work-2025-client-1" ;;
    4) MACHINE_PROFILE="work-2025-client-2" ;;
    *)
      error "Invalid selection: $selection"
      exit 1
      ;;
  esac

  info "Selected profile: $MACHINE_PROFILE"
  echo
fi

# Validate machine profile
if ! is_valid_profile "$MACHINE_PROFILE"; then
  error "Invalid machine profile: $MACHINE_PROFILE"
  echo "Valid profiles: personal, work-2024-client-1, work-2025-client-1, work-2025-client-2"
  exit 1
fi

# Filter SSH keys based on selected machine profile
declare -a SSH_KEYS=()
profile_key_names="$(get_profile_keys "$MACHINE_PROFILE")"

for key_mapping in "${ALL_SSH_KEYS[@]}"; do
  IFS=':' read -r op_name local_name item_vault <<<"$key_mapping"

  # Check if this key is in the profile's allowed list
  if [[ " $profile_key_names " == *" $op_name "* ]]; then
    SSH_KEYS+=("$key_mapping")
  fi
done

# Filter SSH config fragments based on selected machine profile
declare -a SSH_CONFIG_FRAGMENTS=()

for fragment_mapping in "${ALL_SSH_CONFIG_FRAGMENTS[@]}"; do
  IFS=':' read -r fragment_profile op_name local_name item_vault <<<"$fragment_mapping"

  if [[ "$fragment_profile" == "$MACHINE_PROFILE" ]]; then
    SSH_CONFIG_FRAGMENTS+=("$fragment_mapping")
  fi
done

info "Machine profile: $MACHINE_PROFILE"
info "Will download ${#SSH_CONFIG_FRAGMENTS[@]} SSH config fragment(s) for this profile"
info "Will download ${#SSH_KEYS[@]} SSH key(s) for this profile"
echo

sanitize_downloaded_note() {
  local file="$1"

  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/^"//; s/"$//; s/""/"/g' "$file"
  else
    sed -i 's/^"//; s/"$//; s/""/"/g' "$file"
  fi
}

download_secure_note() {
  local item_name="$1"
  local item_vault="$2"
  local destination="$3"

  if op item get "$item_name" --vault="$item_vault" --fields notesPlain 2>/dev/null >"$destination" ||
     op item get "$item_name" --vault="$item_vault" --fields notes 2>/dev/null >"$destination"; then
    if [[ -s "$destination" ]]; then
      sanitize_downloaded_note "$destination"
      chmod 600 "$destination"
      return 0
    fi
  fi

  rm -f "$destination"
  return 1
}

# Dry run mode - just check what's available
if [[ "$DRY_RUN" == "true" ]]; then
  echo
  echo "========================================="
  echo "SSH Config Dry Run - Checking 1Password"
  echo "========================================="
  echo

  info "Checking for SSH configuration items in 1Password..."

  available_items=()
  missing_items=()

  # Check base SSH config
  if op item get "$SSH_CONFIG_BASE_ITEM_NAME" --vault="$SSH_CONFIG_VAULT" >/dev/null 2>&1; then
    available_items+=("$SSH_CONFIG_BASE_ITEM_NAME (Secure Note, vault: $SSH_CONFIG_VAULT)")
  else
    missing_items+=("$SSH_CONFIG_BASE_ITEM_NAME (Secure Note, vault: $SSH_CONFIG_VAULT)")
  fi

  # Check SSH config fragments
  for fragment_mapping in "${SSH_CONFIG_FRAGMENTS[@]}"; do
    IFS=':' read -r fragment_profile op_name local_name item_vault <<<"$fragment_mapping"
    item_vault="${item_vault:-$DEFAULT_VAULT}"

    if op item get "$op_name" --vault="$item_vault" >/dev/null 2>&1; then
      available_items+=("$op_name → $local_name (vault: $item_vault)")
    else
      missing_items+=("$op_name → $local_name (vault: $item_vault)")
    fi
  done

  # Check SSH Keys
  for key_mapping in "${SSH_KEYS[@]}"; do
    IFS=':' read -r op_name local_name item_vault <<<"$key_mapping"
    # Use specified vault or fall back to default
    item_vault="${item_vault:-$DEFAULT_VAULT}"

    if op item get "$op_name" --vault="$item_vault" >/dev/null 2>&1; then
      available_items+=("$op_name → $local_name (vault: $item_vault)")
    else
      missing_items+=("$op_name → $local_name (vault: $item_vault)")
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
    echo "  • Base SSH config: Create a Secure Note named '~/.ssh/config'"
    echo "  • Per-profile config: Create a Secure Note named '~/.ssh/config.d/<profile>.conf'"
    echo "  • SSH Keys: Create SSH Key items with exact names shown above"
    echo "  • Save each item in the vault shown in parentheses"
  fi

  # Check SSH agent
  echo
  info "Checking SSH agent..."
  if [ -S "$HOME/.1password/agent.sock" ]; then
    success "1Password SSH agent socket is available"
  else
    warning "1Password SSH agent socket not found"
    echo "  Enable it in 1Password Settings → Developer → SSH Agent"
  fi

  echo
  success "Dry run complete! No files were modified."
  echo "Run without --dry-run to actually download and apply configurations."
  exit 0
fi

# Unsafe mode warning and confirmation
if [[ "$UNSAFE_MODE" == "true" ]]; then
  echo
  warning "════════════════════════════════════════════════════════════════"
  warning "                    PRIVATE KEY DOWNLOAD MODE"
  warning "════════════════════════════════════════════════════════════════"
  echo
  info "You are about to download PRIVATE SSH keys to disk."
  echo
  echo "This may be necessary if:"
  echo "  • 1Password SSH Agent cannot be installed in your environment"
  echo "  • You're using a restricted system without agent support"
  echo "  • You need keys for backup/migration purposes"
  echo
  warning "Security considerations:"
  echo "  • Private keys will be stored on disk (~/.ssh/)"
  echo "  • Keys may be included in system backups"
  echo "  • Ensure proper file permissions (600)"
  echo "  • Never commit private keys to version control"
  echo
  info "Recommended approach (when possible):"
  echo "  • Use 1Password SSH Agent for authentication"
  echo "  • Keep private keys in 1Password only"
  echo "  • Only store public keys locally for reference"
  echo
  warning "════════════════════════════════════════════════════════════════"
  echo
  if [[ "$ASSUME_YES" == "true" ]]; then
    confirmation="yes"
    warning "Proceeding without prompt because --yes was provided"
  elif [[ "$NO_INPUT" == "true" ]]; then
    error "Unsafe mode requires --yes when --no-input is enabled"
    echo "Re-run with: $0 --profile $MACHINE_PROFILE --unsafe --yes --no-input" >&2
    exit 1
  else
    read -r -p "Do you want to download private keys? (type 'yes' to continue): " confirmation
  fi

  if [[ "${confirmation:-}" != "yes" ]]; then
    info "Cancelled. Running in safe mode (public keys only)."
    UNSAFE_MODE=false
  else
    warning "Private keys will be downloaded to $SSH_DIR"
    echo "Starting in 3 seconds... Press Ctrl+C to cancel"
    sleep 3
  fi
fi

# Create backup directory
mkdir -p "$SSH_DIR" "$SSH_CONFIG_DIR"
mkdir -p "$BACKUP_DIR"
info "Created backup directory: $BACKUP_DIR"

# Backup existing SSH files
backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "$BACKUP_DIR/$(basename "$file")"
    info "Backed up $(basename "$file")"
  fi
}

# Step 1: Backup existing config and keys
info "Backing up existing SSH files..."
backup_file "$SSH_DIR/config"

for fragment_mapping in "${SSH_CONFIG_FRAGMENTS[@]}"; do
  IFS=':' read -r fragment_profile op_name local_name item_vault <<<"$fragment_mapping"
  backup_file "$SSH_CONFIG_DIR/$local_name"
done

for key_mapping in "${SSH_KEYS[@]}"; do
  IFS=':' read -r op_name local_name item_vault <<<"$key_mapping"
  backup_file "$SSH_DIR/$local_name"
  backup_file "$SSH_DIR/${local_name}.pub"
done

# Step 2: Setup base SSH config (from 1Password or example)
info "Setting up base SSH config..."
if download_secure_note "$SSH_CONFIG_BASE_ITEM_NAME" "$SSH_CONFIG_VAULT" "$SSH_DIR/config"; then
  success "Base SSH config downloaded from 1Password and permissions set"
else
  warning "Base SSH config not found in 1Password"

  # Check for config.example as fallback
  if [ -f "$SSH_DIR/config.example" ]; then
    info "Using config.example as template..."
    cp "$SSH_DIR/config.example" "$SSH_DIR/config"
    chmod 600 "$SSH_DIR/config"
    success "Base SSH config created from example template"
    echo "  Note: Ensure it includes both 'Include ~/.ssh/config.d/*.conf' and 'Include ~/.ssh/config.d/*/*.conf'"
  else
    warning "No config.example found either"
    echo "  To add base SSH config to 1Password:"
    echo "  1. Create a Secure Note in 1Password called '~/.ssh/config'"
    echo "  2. Paste your SSH config content in the notes field"
    echo "  3. Save in the '$SSH_CONFIG_VAULT' vault"
  fi
fi

# Step 3: Setup per-profile SSH config fragments
info "Setting up SSH config fragments..."
if [[ "$FORCE_OVERWRITE" == "false" ]]; then
  info "Skipping existing config fragments (use --force to overwrite)"
fi
echo

failed_fragments=()
successful_fragments=()
skipped_fragments=()

for fragment_mapping in "${SSH_CONFIG_FRAGMENTS[@]}"; do
  IFS=':' read -r fragment_profile op_name local_name item_vault <<<"$fragment_mapping"
  item_vault="${item_vault:-$DEFAULT_VAULT}"

  info "Processing $op_name (vault: $item_vault)..."

  if [[ "$FORCE_OVERWRITE" == "false" ]] && [[ -f "$SSH_CONFIG_DIR/$local_name" ]]; then
    info "  Skipping $local_name (already exists)"
    skipped_fragments+=("$local_name (use --force to overwrite)")
    continue
  fi

  if download_secure_note "$op_name" "$item_vault" "$SSH_CONFIG_DIR/$local_name"; then
    successful_fragments+=("$local_name")
    continue
  fi

  if [[ -f "$SSH_CONFIG_DIR/${local_name}.example" ]]; then
    cp "$SSH_CONFIG_DIR/${local_name}.example" "$SSH_CONFIG_DIR/$local_name"
    chmod 600 "$SSH_CONFIG_DIR/$local_name"
    successful_fragments+=("$local_name (from example)")
    warning "Used ${local_name}.example as fallback"
  else
    failed_fragments+=("$op_name → $local_name")
  fi
done

# Step 4: Download SSH Keys
if [[ "$UNSAFE_MODE" == "true" ]]; then
  info "Retrieving SSH keys from 1Password (PRIVATE + PUBLIC)..."
else
  info "Retrieving SSH public keys from 1Password (safe mode)..."
fi

if [[ "$FORCE_OVERWRITE" == "false" ]]; then
  info "Skipping existing keys (use --force to overwrite)"
fi
echo

failed_keys=()
successful_keys=()
skipped_keys=()

for key_mapping in "${SSH_KEYS[@]}"; do
  IFS=':' read -r op_name local_name item_vault <<<"$key_mapping"
  # Use specified vault or fall back to default
  item_vault="${item_vault:-$DEFAULT_VAULT}"

  info "Processing $op_name (vault: $item_vault)..."

  # Check if key already exists and skip if --force not set
  if [[ "$FORCE_OVERWRITE" == "false" ]]; then
    if [[ "$UNSAFE_MODE" == "true" ]]; then
      # In unsafe mode, check for private key
      if [[ -f "$SSH_DIR/$local_name" ]]; then
        info "  Skipping $local_name (already exists)"
        skipped_keys+=("$local_name (use --force to overwrite)")
        continue
      fi
    else
      # In safe mode, check for public key
      if [[ -f "$SSH_DIR/${local_name}.pub" ]]; then
        info "  Skipping ${local_name}.pub (already exists)"
        skipped_keys+=("${local_name}.pub (use --force to overwrite)")
        continue
      fi
    fi
  fi

  # In UNSAFE mode, download private keys
  if [[ "$UNSAFE_MODE" == "true" ]]; then
    # Try as an SSH Key item type (the proper way)
    if op item get "$op_name" --vault="$item_vault" --fields "private key" 2>/dev/null >"$SSH_DIR/$local_name" && [ -s "$SSH_DIR/$local_name" ]; then
      chmod 600 "$SSH_DIR/$local_name"
      successful_keys+=("$local_name (private)")

      # Try to get the public key
      if op item get "$op_name" --vault="$item_vault" --fields "public key" 2>/dev/null >"$SSH_DIR/${local_name}.pub" && [ -s "$SSH_DIR/${local_name}.pub" ]; then
        chmod 644 "$SSH_DIR/${local_name}.pub"
        successful_keys+=("$local_name (public)")
      else
        # Generate public key from private if not stored
        if command -v ssh-keygen >/dev/null 2>&1; then
          if ssh-keygen -y -f "$SSH_DIR/$local_name" >"$SSH_DIR/${local_name}.pub" 2>/dev/null; then
            chmod 644 "$SSH_DIR/${local_name}.pub"
            info "Generated public key for $local_name"
            successful_keys+=("$local_name (public - generated)")
          fi
        fi
      fi
    else
      # Alternative: Try with different field names or as JSON
      if op item get "$op_name" --vault="$item_vault" --format json 2>/dev/null |
        jq -r '.fields[] | select(.id == "private_key").value' >"$SSH_DIR/$local_name" 2>/dev/null &&
        [ -s "$SSH_DIR/$local_name" ]; then
        chmod 600 "$SSH_DIR/$local_name"
        successful_keys+=("$local_name (private)")

        # Get public key
        if op item get "$op_name" --vault="$item_vault" --format json 2>/dev/null |
          jq -r '.fields[] | select(.id == "public_key").value' >"$SSH_DIR/${local_name}.pub" 2>/dev/null &&
          [ -s "$SSH_DIR/${local_name}.pub" ]; then
          chmod 644 "$SSH_DIR/${local_name}.pub"
          successful_keys+=("$local_name (public)")
        fi
      else
        failed_keys+=("$op_name → $local_name")
        rm -f "$SSH_DIR/$local_name" # Remove empty file if created
      fi
    fi
  else
    # SAFE MODE: Only download public keys
    if op item get "$op_name" --vault="$item_vault" --fields "public key" 2>/dev/null >"$SSH_DIR/${local_name}.pub" && [ -s "$SSH_DIR/${local_name}.pub" ]; then
      chmod 644 "$SSH_DIR/${local_name}.pub"
      successful_keys+=("$local_name (public only)")
    else
      # Alternative: Try with JSON format
      if op item get "$op_name" --vault="$item_vault" --format json 2>/dev/null |
        jq -r '.fields[] | select(.id == "public_key").value' >"$SSH_DIR/${local_name}.pub" 2>/dev/null &&
        [ -s "$SSH_DIR/${local_name}.pub" ]; then
        chmod 644 "$SSH_DIR/${local_name}.pub"
        successful_keys+=("$local_name (public only)")
      else
        # Try to extract from the SSH key item itself
        if op item get "$op_name" --vault="$item_vault" --format json 2>/dev/null |
          jq -r '.public_key // empty' >"$SSH_DIR/${local_name}.pub" 2>/dev/null &&
          [ -s "$SSH_DIR/${local_name}.pub" ]; then
          chmod 644 "$SSH_DIR/${local_name}.pub"
          successful_keys+=("$local_name (public only)")
        else
          warning "Could not retrieve public key for $op_name"
          failed_keys+=("$op_name → ${local_name}.pub")
          rm -f "$SSH_DIR/${local_name}.pub" # Remove empty file if created
        fi
      fi
    fi
  fi
done

# Step 5: Verify SSH agent access
info "Checking SSH agent..."
if [ -S "$HOME/.1password/agent.sock" ]; then
  success "1Password SSH agent is available"
else
  warning "1Password SSH agent socket not found"
  echo "  Enable it in 1Password Settings → Developer → SSH Agent"
fi

# Step 6: Report results
echo
echo "========================================="
echo "SSH Setup Summary"
echo "========================================="

if [ ${#successful_fragments[@]} -gt 0 ]; then
  success "Successfully configured SSH fragments:"
  for fragment in "${successful_fragments[@]}"; do
    echo "  • $fragment"
  done
fi

if [ ${#skipped_fragments[@]} -gt 0 ]; then
  echo
  info "Skipped existing SSH fragments:"
  for fragment in "${skipped_fragments[@]}"; do
    echo "  ↷ $fragment"
  done
fi

if [ ${#failed_fragments[@]} -gt 0 ]; then
  echo
  warning "Failed to download SSH fragments:"
  for fragment in "${failed_fragments[@]}"; do
    echo "  ✗ $fragment"
  done
  echo
  echo "To add SSH config fragments to 1Password:"
  echo "  1. Open 1Password"
  echo "  2. Create new item → Secure Note"
  echo "  3. Name it exactly as shown above (before the →)"
  echo "  4. Paste your SSH host stanzas in the notes field"
  echo "  5. Save in the vault shown in the error message"
fi

if [ ${#successful_keys[@]} -gt 0 ]; then
  success "Successfully downloaded keys:"
  for key in "${successful_keys[@]}"; do
    echo "  • $key"
  done
fi

if [ ${#skipped_keys[@]} -gt 0 ]; then
  echo
  info "Skipped existing keys:"
  for key in "${skipped_keys[@]}"; do
    echo "  ↷ $key"
  done
fi

if [ ${#failed_keys[@]} -gt 0 ]; then
  echo
  warning "Failed to download keys:"
  for key in "${failed_keys[@]}"; do
    echo "  ✗ $key"
  done
  echo
  echo "To add SSH keys to 1Password:"
  echo "  1. Open 1Password"
  echo "  2. Create new item → SSH Key"
  echo "  3. Name it exactly as shown above (before the →)"
  echo "  4. Paste your private key content"
  echo "  5. Save in the vault shown in the error message"
fi

# Step 7: Test SSH connections
echo
info "Testing SSH connections..."
echo "You can test your connections with:"
echo "  ssh -T git@github.com"
echo "  ssh -T git@github-work-2025-client-1"
echo "  ssh -T git@ado-work-2025-client-2"

echo
success "SSH setup complete!"
echo "Backups saved to: $BACKUP_DIR"
