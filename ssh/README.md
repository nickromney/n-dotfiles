# SSH Configuration

Template and management scripts for secure SSH configuration using 1Password as the source of truth.

## Directory Structure

```text
ssh/
└── .ssh/
    └── config.example  # Template SSH config with 1Password agent setup
```

## Why This Approach?

SSH configuration contains sensitive information that shouldn't be in version control:

- **Private keys** - Must never be committed
- **Hostnames** - Can reveal infrastructure details
- **Usernames** - Can expose account information
- **Client names** - Can leak business relationships

## Secure Setup via 1Password

The setup script manages SSH configuration with security in mind:

### Default (Safe) Mode

- Downloads SSH config from 1Password (Secure Note)
- Downloads **public keys only** for reference
- Private keys remain in 1Password
- Uses 1Password SSH Agent for authentication

### Unsafe Mode (`--unsafe` flag)

- Downloads both private and public keys to disk
- Required for environments where 1Password SSH Agent isn't available
- Requires explicit confirmation
- Use only when absolutely necessary

### What Gets Configured

| 1Password Item                     | Safe Mode (Default)                  | Unsafe Mode                          | Purpose                          |
| ---------------------------------- | ------------------------------------ | ------------------------------------ | -------------------------------- |
| `~/.ssh/config` (Secure Note)      | `~/.ssh/config`                      | `~/.ssh/config`                      | Complete SSH configuration       |
| `personal_github_authentication`   | `~/.ssh/personal_github_authentication.pub` | `~/.ssh/personal_github_authentication` + `.pub` | Personal GitHub authentication   |
| `personal_github_signing`          | `~/.ssh/personal_github_signing.pub` | `~/.ssh/personal_github_signing` + `.pub` | GitHub commit signing       |
| `work_2024_client_1_aws`           | `~/.ssh/work_2024_client_1_aws.pem.pub` | `~/.ssh/work_2024_client_1_aws.pem` + `.pub` | AWS EC2 access        |
| `work_2025_client_1_github`        | `~/.ssh/work_2025_client_1_github.pub` | `~/.ssh/work_2025_client_1_github` + `.pub` | Work GitHub access      |

### Running Setup

The setup script `setup-ssh-from-1password.sh` (in repository root) handles everything:

```bash
# Safe mode (default) - config + public keys only
./setup-ssh-from-1password.sh

# Check what would be downloaded without making changes
./setup-ssh-from-1password.sh --dry-run

# Unsafe mode - download private keys (requires confirmation)
./setup-ssh-from-1password.sh --unsafe

# Or automatic during Mac setup
./setup-personal-mac.sh  # Includes SSH setup as Step 7 (safe mode)
```

## 1Password Configuration

### SSH Config (Secure Note)

1. Create a **Secure Note** in 1Password
2. Name it: `~/.ssh/config`
3. Paste your complete SSH configuration in the notes field
4. Save to your vault (default: "Private")

### SSH Keys (SSH Key Items)

For each key:

1. Create an **SSH Key** item in 1Password
2. Use the exact names from the table above
3. Paste the private key content
4. 1Password automatically extracts the public key
5. Tag appropriately for organization

## Security Notes

- Keys use generic names (`client_1`) instead of actual client names
- Year-based versioning for rotating keys (`2024`, `2025`)
- All sensitive data encrypted in 1Password
- Automatic backups created before any changes
- Proper permissions set (600 for private keys, 644 for public)

## Troubleshooting

### Missing 1Password CLI

```bash
brew install --cask 1password-cli
```

### Not Signed Into 1Password

```bash
eval $(op signin)
```

### SSH Agent Not Working

Ensure 1Password SSH Agent is enabled:

- 1Password Settings → Developer → SSH Agent

### Testing Connections

```bash
# Personal GitHub
ssh -T git@github.com

# Work GitHub
ssh -T git@github-work

# AWS instances (if configured)
ssh <hostname>
```
