# n-dotfiles

An opinionated dotfiles setup designed to:

- work on Mac OS X with brew
- work on Ubuntu (particularly in dev containers and for GitHub Actions)
- be simple enough to reason about at a glance

## Design considerations

- I work on Mac OS X
- I'm a DevOps Engineer by recent training, so like idempotent code
- The setup is three declarative layers, each owned by a tool someone
  else maintains:

| Layer | Owns | Source of truth |
|-------|------|-----------------|
| `brew bundle` | Casks, fonts, Mac App Store apps, mac-only formulae | [Brewfile](Brewfile) ([Brewfile.posix](Brewfile.posix) on Linux) |
| `mise install` | Cross-platform CLI tools and language runtimes | [mise/.config/mise/config.toml](mise/.config/mise/config.toml) |
| `stow` | Dotfile symlinks into `$HOME` | The stow trees (`zsh/`, `git/`, `nvim/`, ...) via [stow.sh](stow.sh) |

I looked at [nix flakes](https://nixos.wiki/wiki/flakes) but although I'm often tweaking my configuration, I don't need to set up whole new machines enough to warrant it. This [blog](https://jvns.ca/blog/2023/11/11/notes-on-nix-flakes/) from Julia Evans convinced me away from it.

AI CLIs (claude, codex, opencode, copilot) are deliberately unmanaged:
they self-update via their own native installers, and pinning them
through a package manager just fights the updater. Install them with
their official one-liners and let them look after themselves.

## Quick Start

### Fresh macOS Installation

For a brand new Mac, use the bootstrap script:

```bash
# Create directory structure and clone
mkdir -p ~/Developer/personal
cd ~/Developer/personal
git clone https://github.com/nickromney/n-dotfiles.git
cd n-dotfiles

# Preview, then run: Homebrew + Brewfile + stow + mise
./bootstrap.sh --dry-run --no-input --skip-1password
./bootstrap.sh

# Apply macOS settings (dock, defaults)
make configure
```

Or run the whole personal flow (bootstrap + macOS settings + SSH from
1Password) in one script:

```bash
./setup-personal-mac.sh --dry-run
./setup-personal-mac.sh
```

### Existing System

```bash
make install    # brew bundle + stow + mise install (idempotent)
make update     # update brew, mise, and Mac App Store packages
```

### Stow-only machine (e.g. work)

The work machine gets dotfiles only — no package management:

```bash
git clone https://github.com/nickromney/n-dotfiles.git
cd n-dotfiles
./stow.sh --dry-run   # preview (shows conflicts with existing files)
./stow.sh             # symlink everything
./stow.sh zsh git     # or just selected packages
```

`./stow.sh --adopt` pulls pre-existing real files into the repo if you
want to keep them — review with `git diff` afterwards.

### Linux

```bash
brew bundle --file Brewfile.posix   # Homebrew on Linux formulae
./stow.sh                           # symlink dotfiles
mise install                        # same CLI tools as the Mac
```

## Using the Makefile

```bash
make install       # brew bundle + stow + mise install
make stow          # symlink dotfiles only
make update        # update brew, mise, mas (and rustup if present)
make configure     # apply macOS settings (MACOS_PROFILE=personal|work)
make lint          # shellcheck + markdownlint
make test          # full BATS suite
make audit         # drift report: installed vs Brewfile/mise config
```

> **Note:** Mac App Store installs require you to sign in via the App
> Store app and click "Get" once per app before `brew bundle` can
> install them via `mas`.

## Tool Management

### Adding a CLI tool

Add one line to [mise/.config/mise/config.toml](mise/.config/mise/config.toml):

```toml
[tools]
kubectl = "latest"                        # short name from `mise registry`
"github:cilium/hubble" = "latest"         # or any GitHub release directly
```

Then run `mise install`. The same entry works on macOS and Linux.
Useful commands:

```bash
mise registry <name>   # check whether a tool has a short name
mise ls                # what is installed/active
mise upgrade           # update everything to latest
mise use -g foo@latest # add + install a global tool in one step
```

### Adding a mac app, font, or formula

Add a `cask`/`brew`/`mas` line to the [Brewfile](Brewfile) and run
`make install` (or `brew bundle --file Brewfile`).

To find drift in either direction, run `make audit` — it reports
Brewfile entries missing from the machine and installed packages
missing from the Brewfile.

## Harness Assets

Private harness assets are synced from the optional sibling
`../harnesses-private` repo into the global, Claude, and Codex skill roots.
Run this from the `n-dotfiles` repo root:

```bash
./scripts/sync-private-harness-assets.sh --dry-run
./scripts/sync-private-harness-assets.sh --execute
```

Use `--private-root <path>` if the private harness repo is not a sibling of
`n-dotfiles`.

## macOS System Configuration

Light-touch macOS configuration management:

```bash
# Show current system settings
./_macos/macos.sh

# Apply personal configuration
./_macos/macos.sh personal.yaml

# Dry run to preview changes
./_macos/macos.sh -d personal.yaml

# Non-interactive apply with follow-up instructions instead of prompts
./_macos/macos.sh --no-input personal.yaml

# Equivalent Makefile helper
make configure
```

See [_macos/README.md](_macos/README.md) for detailed macOS configuration options.

## 1Password Integration

This repository includes comprehensive 1Password integration for secure credential and configuration management.

### SSH Configuration Management

The `setup-ssh-from-1password.sh` script manages SSH configuration with security by default:

#### Default (Safe) Mode

```bash
# Download base SSH config + per-profile fragment + public keys only
./setup-ssh-from-1password.sh --profile personal --no-input

# Check what's available without downloading
./setup-ssh-from-1password.sh --profile personal --dry-run --no-input
```

In safe mode:

- Downloads base SSH config from 1Password (stored as Secure Note)
- Downloads a per-profile SSH config fragment from 1Password
- Downloads **public keys only** for reference
- Private keys remain in 1Password
- Uses 1Password SSH Agent for authentication

#### Unsafe Mode (When 1Password SSH Agent Isn't Available)

```bash
# Download private keys (requires explicit confirmation)
./setup-ssh-from-1password.sh --profile personal --unsafe

# Non-interactive private-key download
./setup-ssh-from-1password.sh --profile personal --unsafe --yes --no-input
```

Use unsafe mode when:

- 1Password SSH Agent cannot be installed in your environment
- You're using a restricted system without agent support
- You need keys for backup/migration purposes

### Git Configuration Management

The `setup-gitconfig-from-1password.sh` script manages work-specific Git configurations:

```bash
# Download work Git config from 1Password
./setup-gitconfig-from-1password.sh

# Check availability without downloading
./setup-gitconfig-from-1password.sh --dry-run
```

This allows you to:

- Store work-specific Git config in 1Password
- Automatically apply it to `~/Developer/work/.gitconfig_include`
- Keep work email and GitHub Enterprise settings secure
- Use `includeIf` in main `.gitconfig` for automatic switching

### AWS Credentials Helper

The `aws/.aws/aws-1password` script provides on-demand AWS credential fetching:

```bash
# Configure AWS CLI to use 1Password
aws configure set credential_process "$HOME/.aws/aws-1password --username default"

# For different profiles
aws configure set credential_process "$HOME/.aws/aws-1password --username tfcli" --profile terraform
```

This approach:

- Never stores AWS credentials on disk
- Fetches credentials from 1Password when needed
- Works seamlessly with AWS CLI and SDKs
- Supports multiple AWS accounts/profiles

### Setting Up 1Password Items

#### SSH Keys

1. Open 1Password and create new item → SSH Key
2. Name it exactly as expected by the script:
   - `personal_github_authentication`
   - `personal_github_signing`
   - `work_2024_client_1_aws`
   - `work_2025_client_1_github`
   - `work_2025_client_2_github`
   - `work_2025_client_2_gitea`
   - `work_2025_client_2_ado`
3. Paste your private key
4. Save to the vault expected by the script for that key

#### SSH Config

1. Create new item → Secure Note
2. Name it: `~/.ssh/config`
3. Add your base SSH configuration, for example:

   ```sshconfig
   Host *
     IdentityAgent "~/.1password/agent.sock"

   Include ~/.ssh/config.d/*.conf
   Include ~/.ssh/config.d/*/*.conf
   ```

4. Save it in the vault selected by `SSH_CONFIG_VAULT` or `VAULT`

#### SSH Config Fragments

1. Create new item → Secure Note
2. Name it as one of:
   - `~/.ssh/config.d/personal.conf`
   - `~/.ssh/config.d/work-2024-client-1.conf`
   - `~/.ssh/config.d/work-2025-client-1.conf`
   - `~/.ssh/config.d/work-2025-client-2.conf`
3. Add only the host stanzas for that profile
4. Save it in the same vault as that profile's SSH keys

#### Git Config

1. Create new item → Secure Note
2. Name it: `work .gitconfig_include`
3. Add your work-specific Git configuration:

   ```ini
   [url "github-work:OrgName/"]
     insteadOf = git@github.com:OrgName/
     insteadOf = https://github.com/OrgName/

   [url "git@ado-work-2025-client-2:v3/ORG/PROJECT/"]
     insteadOf = git@ssh.dev.azure.com:v3/ORG/PROJECT/

   [user]
     email = work@company.com
   ```

4. Save to "Private" vault

#### AWS Credentials

1. Create new item → API Credential (or custom item)
2. Name it based on your mapping (e.g., `AWSCredsUsernameDefault`)
3. Add fields:
   - `ACCESS_KEY`: Your AWS Access Key ID
   - `SECRET_KEY`: Your AWS Secret Access Key
4. Save to "CLI" vault (or adjust in script)

### Security Benefits

- **No secrets in version control**: All sensitive data stays in 1Password
- **Encrypted at rest**: 1Password handles all encryption
- **Audit trail**: 1Password logs all access to credentials
- **Easy rotation**: Update credentials in one place
- **Team sharing**: Safely share vaults with team members
- **MFA protection**: Additional security with 1Password's MFA

## Package Manager Setup

### Installing Rust/Cargo

The dotfiles manage PATH configuration for Rust/Cargo in `zsh/.zshrc`. To prevent rustup from modifying your shell files during installation:

```bash
# Install Rust without modifying shell configuration
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path
```

The `--no-modify-path` flag prevents rustup from adding its own PATH configuration to your shell files, since the dotfiles already handle `$HOME/.cargo/bin` in the managed PATH configuration.

Alternatively, you can:

- Set `RUSTUP_MODIFY_PATH=false` before running the installer
- Choose "Customize installation" (option 2) and decline PATH modification

### PATH Management

The ZSH configuration automatically adds tool directories to PATH if they exist:

- `$HOME/.local/bin` - Local user binaries
- `$HOME/.cargo/bin` - Rust/Cargo binaries
- `$HOME/.local/share/mise/shims` - mise-managed tools (non-interactive shells)
- `$HOME/.lmstudio/bin` - LM Studio CLI

Each directory is only added if it exists, preventing errors on partial installations. Interactive zsh shells also run `mise activate`, which keeps tool versions in sync per directory.

## Shell Configuration

The ZSH configuration (in `zsh/.zshrc`) uses **defensive programming** - every tool is checked before use, ensuring it works across all environments (personal Mac, work Mac, fresh installs, dev containers).

### FZF + Bat File Preview Helpers

Quick file finding with syntax-highlighted previews:

```bash
f          # Launch fzf fuzzy finder
bf         # Select file, open in bat pager
nf         # Select file, open in neovim
pf         # Select file, copy path to clipboard
```

All commands show bat-powered syntax highlighting with line numbers in the preview pane.

### Conditional Features

The shell adapts based on installed tools:

- **Completions**: kubectl, gh, and other CLI tools
- **Integrations**: direnv, zoxide, starship, mise
- **Plugins**: zsh-autosuggestions, zsh-syntax-highlighting (via Homebrew)
- **Aliases**: Conditional git, navigation, and file listing shortcuts

See [zsh/README.md](zsh/README.md) for complete shell configuration documentation.

## Directory Structure

```shell
.
├── Brewfile         # macOS layer: casks, fonts, mas apps, formulae
├── Brewfile.posix   # Linux (Homebrew on Linux) formulae
├── bootstrap.sh     # Fresh-Mac bootstrap: brew + Brewfile + stow + mise
├── stow.sh          # Stow entrypoint (all a work machine needs)
├── Makefile         # install / stow / update / configure / test targets
├── mise/            # Stow tree for ~/.config/mise/config.toml (CLI tools)
├── _macos/          # macOS system configuration
│   ├── macos.sh     # macOS settings script
│   └── *.yaml       # Settings profiles (personal, work)
├── _test/           # BATS suites, shellcheck, Lima smoke tests
└── */               # Stow directories for dotfiles
    ├── aerospace/   # Tiling window manager
    ├── git/         # Git configuration
    ├── nvim/        # Neovim config
    ├── tmux/        # Tmux config
    ├── zsh/         # Zsh configuration
    └── ...          # Other tool configs
```

## Testing

The repository includes a test suite using BATS (Bash Automated Testing System):

```bash
# Install BATS (required for testing)
brew install bats-core  # macOS
sudo apt-get install bats  # Ubuntu/Debian

# Run all tests
./_test/run_tests.sh

# Run a single suite
bats _test/makefile.bats
```

### Local Git hooks

Local validation runs through lefthook.

```bash
# Install hooks
lefthook install
# or
make hooks

# Skip a hook for an intentional one-off
LEFTHOOK=0 git commit -m "message"
git push --no-verify

# Run on-demand GitHub CI
gh workflow run test.yml
```

### Ubuntu 24.04 Lima smoke test (non-mac/POSIX path)

A Lima-based Ubuntu 24.04 smoke test validates the Linux path:
Homebrew on Linux + `Brewfile.posix`, `stow.sh` in a fresh `$HOME`,
and the global mise config.

```bash
# Start/create test VM
make test-lima-up

# Run POSIX/non-mac smoke tests in the VM
make test-lima-run

# One-shot: start VM (if needed) + run smoke tests
make test-lima

# Optional lifecycle helpers
make test-lima-status
make test-lima-down
make test-lima-destroy

# Optional: make shellcheck failures blocking for this VM run
STRICT_SHELLCHECK=true make test-lima-run
```

See [_test/README.md](_test/README.md) for suite structure and the
mocking framework.

## Inspiration

- [idcrook](https://github.com/idcrook/i-dotfiles) - elegant usage of GNU stow
- [Typecraft Dev](https://github.com/typecraft-dev/dotfiles) - because of the excellent YouTube video walkthroughs - "be a better nerd"
- [Omer Hamerman / DevOpsToolbox](https://github.com/omerxx/dotfiles) - again, a fan of the YouTube video walkthroughs
- [Christian Sutter](https://github.com/csutter/punkt) - I used to work with Christian, and learned lots from pair programming with him.
- [Rob / Tech Craft](https://www.youtube.com/@tech_craft/videos) - Not posted for a while, but excellent videos
