# SSH Configuration

Template and management scripts for secure SSH configuration using 1Password as the source of truth.

## Directory Structure

```text
ssh/
└── .ssh/
    ├── config.example
    └── config.d/
        ├── local/
        │   └── gitea.conf.example
        ├── personal.conf.example
        ├── work-2024-client-1.conf.example
        ├── work-2025-client-1.conf.example
        └── work-2025-client-2.conf.example
```

Optional grouped fragments can live one directory deep under `config.d/`, for
example `~/.ssh/config.d/local/gitea.conf`.

## Why This Approach?

SSH configuration contains sensitive information that shouldn't be in version control:

- **Private keys** - Must never be committed
- **Hostnames** - Can reveal infrastructure details
- **Usernames** - Can expose account information
- **Client names** - Can leak business relationships

## Secure Setup via 1Password

The setup script manages SSH configuration with security in mind:

### Default (Safe) Mode

- Downloads base SSH config from 1Password (Secure Note)
- Downloads one per-profile SSH config fragment from 1Password
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
| `~/.ssh/config` (Secure Note)      | `~/.ssh/config`                      | `~/.ssh/config`                      | Base SSH configuration           |
| `~/.ssh/config.d/personal.conf`    | `~/.ssh/config.d/personal.conf`      | `~/.ssh/config.d/personal.conf`      | Personal host stanzas            |
| `~/.ssh/config.d/work-2024-client-1.conf` | `~/.ssh/config.d/work-2024-client-1.conf` | `~/.ssh/config.d/work-2024-client-1.conf` | Client 1 host stanzas     |
| `~/.ssh/config.d/work-2025-client-1.conf` | `~/.ssh/config.d/work-2025-client-1.conf` | `~/.ssh/config.d/work-2025-client-1.conf` | Client 1 host stanzas     |
| `~/.ssh/config.d/work-2025-client-2.conf` | `~/.ssh/config.d/work-2025-client-2.conf` | `~/.ssh/config.d/work-2025-client-2.conf` | Client 2 host stanzas     |
| `personal_github_authentication`   | `~/.ssh/personal_github_authentication.pub` | `~/.ssh/personal_github_authentication` + `.pub` | Personal GitHub authentication   |
| `personal_github_signing`          | `~/.ssh/personal_github_signing.pub` | `~/.ssh/personal_github_signing` + `.pub` | GitHub commit signing       |
| `work_2024_client_1_aws`           | `~/.ssh/work_2024_client_1_aws.pem.pub` | `~/.ssh/work_2024_client_1_aws.pem` + `.pub` | AWS EC2 access        |
| `work_2025_client_1_github`        | `~/.ssh/work_2025_client_1_github.pub` | `~/.ssh/work_2025_client_1_github` + `.pub` | Work GitHub access      |
| `work_2025_client_2_github`        | `~/.ssh/work_2025_client_2_github.pub` | `~/.ssh/work_2025_client_2_github` + `.pub` | Work GitHub access      |
| `work_2025_client_2_gitea`         | `~/.ssh/work_2025_client_2_gitea.pub` | `~/.ssh/work_2025_client_2_gitea` + `.pub` | Work Gitea access       |
| `work_2025_client_2_ado`           | `~/.ssh/work_2025_client_2_ado.pub` | `~/.ssh/work_2025_client_2_ado` + `.pub` | Azure DevOps access     |

### Running Setup

The setup script `setup-ssh-from-1password.sh` (in repository root) handles everything:

```bash
# Safe mode (default) - base config + per-profile fragment + public keys only
./setup-ssh-from-1password.sh

# Check what would be downloaded without making changes
./setup-ssh-from-1password.sh --dry-run

# Unsafe mode - download private keys (requires confirmation)
./setup-ssh-from-1password.sh --unsafe

# Or automatic during Mac setup
./setup-personal-mac.sh  # Includes SSH setup as Step 7 (safe mode)
```

## 1Password Configuration

### Base SSH Config (Secure Note)

1. Create a **Secure Note** in 1Password
2. Name it: `~/.ssh/config`
3. Add your machine-wide defaults, including:

   ```sshconfig
   Host *
     IdentityAgent "~/.1password/agent.sock"

   Include ~/.ssh/config.d/*.conf
   Include ~/.ssh/config.d/*/*.conf
   ```

4. Save it to the vault selected by `SSH_CONFIG_VAULT` or `VAULT`

### Per-Profile SSH Config Fragments (Secure Notes)

Create one Secure Note per profile and store it in the same vault as that profile's keys:

- `~/.ssh/config.d/personal.conf`
- `~/.ssh/config.d/work-2024-client-1.conf`
- `~/.ssh/config.d/work-2025-client-1.conf`
- `~/.ssh/config.d/work-2025-client-2.conf`

The setup script downloads only the fragment for the selected profile and leaves the others in place, which makes multi-profile machines additive instead of overwrite-only.
It also supports grouped fragments one directory deep under `~/.ssh/config.d/`.

### SSH Keys (SSH Key Items)

For each key:

1. Create an **SSH Key** item in 1Password
2. Use the exact names from the table above
3. Paste the private key content
4. 1Password automatically extracts the public key
5. Tag appropriately for organization

### Azure DevOps Setup

Azure DevOps needs both sides configured:

1. Create an SSH Key item in 1Password named `work_2025_client_2_ado`
2. Add that item's public key to Azure DevOps at User settings -> SSH public keys
3. Add a host stanza to `~/.ssh/config.d/work-2025-client-2.conf` that points `ssh.dev.azure.com` at `~/.ssh/work_2025_client_2_ado.pub`
4. Run `./setup-ssh-from-1password.sh --profile work-2025-client-2` on the target machine

Example host stanza:

```sshconfig
Host ado-work-2025-client-2
  HostName ssh.dev.azure.com
  User git
  IdentityFile ~/.ssh/work_2025_client_2_ado.pub
  IdentitiesOnly yes
```

Example clone URL using that alias:

```bash
git clone git@ado-work-2025-client-2:v3/ORG/PROJECT/REPO
```

If OpenSSH warns that the connection is not using a post-quantum key exchange algorithm when talking to `ssh.dev.azure.com`, that warning is about the server's key exchange support, not whether your uploaded key is valid.

### Gitea Setup

For a dedicated Gitea key on the `work-2025-client-2` profile:

1. Create an SSH Key item in 1Password named `work_2025_client_2_gitea`
2. Add that item's public key to Gitea at User Settings -> SSH / GPG Keys
3. Add a host stanza to `~/.ssh/config.d/work-2025-client-2.conf` that points your local or forwarded Gitea host at `~/.ssh/work_2025_client_2_gitea.pub`
4. Run `./setup-ssh-from-1password.sh --profile work-2025-client-2` on the target machine

Example host stanza:

```sshconfig
Host gitea-work-2025-client-2
  HostName gitea.127.0.0.1.sslip.io
  Port 2222
  User git
  IdentityFile ~/.ssh/work_2025_client_2_gitea.pub
  IdentitiesOnly yes
```

Example clone URL using that alias:

```bash
git clone ssh://git@gitea-work-2025-client-2:2222/OWNER/REPO.git
```

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
ssh -T git@github-work-2025-client-1

# Azure DevOps
ssh -T git@ado-work-2025-client-2

# AWS instances (if configured)
ssh <hostname>
```
