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

SSH configuration can be managed two ways:

1. **Preferred**: Store complete config in 1Password (Secure Note)
2. **Fallback**: Use `config.example` as a template if no 1Password config exists

The setup script tries 1Password first, then falls back to the example template.

### What Gets Configured

| 1Password Item                     | Local File                           | Purpose                          |
| ---------------------------------- | ------------------------------------ | -------------------------------- |
| `SSH Config` (Secure Note)         | `~/.ssh/config`                      | Complete SSH configuration       |
| `github_personal_authentication`   | `~/.ssh/id_ed25519`                  | Personal GitHub authentication   |
| `github_personal_signing`          | `~/.ssh/github_personal_signing`     | GitHub commit signing            |
| `aws_work_2024_client_1`           | `~/.ssh/aws_work_2024_client_1.pem` | AWS EC2 access (client 1)        |
| `github_work_2025_client_1`        | `~/.ssh/github_work_2025_client_1`   | Work GitHub (client anonymized)  |

### Running Setup

The setup script `setup-ssh-from-1password.sh` (in repository root) handles everything:

```bash
# Manual setup
./setup-ssh-from-1password.sh

# Or automatic during Mac setup
./setup-personal-mac.sh  # Includes SSH setup as Step 7
```

## 1Password Configuration

### SSH Config (Secure Note)

1. Create a **Secure Note** in 1Password
2. Name it: `SSH Config`
3. Paste your complete SSH configuration in the notes field
4. Save to your vault (default: "Personal")

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
