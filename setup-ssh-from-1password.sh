#!/usr/bin/env bash

# Setup SSH config and keys from 1Password
# This script retrieves SSH configuration and private keys from 1Password

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}ℹ${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }

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
readonly VAULT="Personal" # Adjust to your vault name
readonly SSH_DIR="$HOME/.ssh"
declare BACKUP_DIR
BACKUP_DIR="$SSH_DIR/backups/$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR

# SSH Keys to download from 1Password
# Format: "1password_item_name:local_filename"
# Use generic names to avoid exposing client information
declare -a SSH_KEYS=(
  "github_personal_authentication:id_ed25519"
  "github_personal_signing:github_personal_signing"
  "aws_work_2024_client_1:aws_work_2024_client_1.pem"
  "github_work_2025_client_1:github_work_2025_client_1"
)

# Create backup directory
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

for key_mapping in "${SSH_KEYS[@]}"; do
  local_name="${key_mapping#*:}"
  backup_file "$SSH_DIR/$local_name"
  backup_file "$SSH_DIR/${local_name}.pub"
done

# Step 2: Setup SSH Config (from 1Password or example)
info "Setting up SSH config..."
if op item get "SSH Config" --vault="$VAULT" --fields notes 2>/dev/null >"$SSH_DIR/config"; then
  chmod 600 "$SSH_DIR/config"
  success "SSH config downloaded from 1Password and permissions set"
else
  warning "SSH config not found in 1Password"

  # Check for config.example as fallback
  if [ -f "$SSH_DIR/config.example" ]; then
    info "Using config.example as template..."
    cp "$SSH_DIR/config.example" "$SSH_DIR/config"
    chmod 600 "$SSH_DIR/config"
    success "SSH config created from example template"
    echo "  Note: Update the config with your actual hosts and keys"
  else
    warning "No config.example found either"
    echo "  To add SSH config to 1Password:"
    echo "  1. Create a Secure Note in 1Password called 'SSH Config'"
    echo "  2. Paste your SSH config content in the notes field"
    echo "  3. Save in the '$VAULT' vault"
  fi
fi

# Step 3: Download SSH Keys
info "Retrieving SSH keys from 1Password..."
failed_keys=()
successful_keys=()

for key_mapping in "${SSH_KEYS[@]}"; do
  IFS=':' read -r op_name local_name <<<"$key_mapping"

  info "Downloading $op_name..."

  # Try as an SSH Key item type (the proper way)
  if op item get "$op_name" --vault="$VAULT" --fields "private key" 2>/dev/null >"$SSH_DIR/$local_name" && [ -s "$SSH_DIR/$local_name" ]; then
    chmod 600 "$SSH_DIR/$local_name"
    successful_keys+=("$local_name (private)")

    # Try to get the public key
    if op item get "$op_name" --vault="$VAULT" --fields "public key" 2>/dev/null >"$SSH_DIR/${local_name}.pub" && [ -s "$SSH_DIR/${local_name}.pub" ]; then
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
    if op item get "$op_name" --vault="$VAULT" --format json 2>/dev/null |
      jq -r '.fields[] | select(.id == "private_key").value' >"$SSH_DIR/$local_name" 2>/dev/null &&
      [ -s "$SSH_DIR/$local_name" ]; then
      chmod 600 "$SSH_DIR/$local_name"
      successful_keys+=("$local_name (private)")

      # Get public key
      if op item get "$op_name" --vault="$VAULT" --format json 2>/dev/null |
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
done

# Step 4: Verify SSH agent access
info "Checking SSH agent..."
if [ -S "$HOME/.1password/agent.sock" ]; then
  success "1Password SSH agent is available"
else
  warning "1Password SSH agent socket not found"
  echo "  Enable it in 1Password Settings → Developer → SSH Agent"
fi

# Step 5: Report results
echo
echo "========================================="
echo "SSH Setup Summary"
echo "========================================="

if [ ${#successful_keys[@]} -gt 0 ]; then
  success "Successfully downloaded keys:"
  for key in "${successful_keys[@]}"; do
    echo "  • $key"
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
  echo "  5. Save in the '$VAULT' vault"
fi

# Step 6: Test SSH connections
echo
info "Testing SSH connections..."
echo "You can test your connections with:"
echo "  ssh -T git@github.com"
echo "  ssh -T git@github-work"

echo
success "SSH setup complete!"
echo "Backups saved to: $BACKUP_DIR"
