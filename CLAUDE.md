# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Markdown Standards

All markdown files in this repository MUST be checked against `.markdownlint.json` configuration. When creating or editing markdown:

1. Run `markdownlint <file>.md` to check for issues
2. Use `markdownlint --fix <file>.md` to auto-fix where possible
3. Follow the configured rules (line length ignored, fenced code blocks preferred)
4. Always add language specifiers to code blocks
5. Ensure proper spacing around headers and lists
6. Files must end with a single newline

## Repository Overview

This is a personal dotfiles repository designed for cross-platform configuration management. It uses GNU Stow for symlink management and supports multiple package managers (brew, arkade, uv, cargo, apt). The design is modular and idempotent.

## Key Commands

### Quick Start (Recommended)

```bash
# Fresh macOS installation (installs Homebrew, yq, stow)
./bootstrap.sh

# Personal Mac full setup (packages + macOS settings + stow + SSH)
./setup-personal-mac.sh

# Work Mac full setup
./setup-work-mac.sh

# Using Makefile (most convenient)
make common install          # Install common tools only
make personal stow           # Personal setup + stow configurations
make focus-vscode            # Install VSCode + 38 extensions
VSCODE_CLI=cursor make focus-vscode  # Install extensions for Cursor
```

### Direct install.sh Usage

```bash
# Install packages and stow configurations
./install.sh -s

# Dry run mode (preview changes without making them)
./install.sh -d -s

# Force mode (adopt existing files during stow)
./install.sh -s -f

# Update existing packages
./install.sh -u

# Verbose output
./install.sh -v

# Install only (no stowing)
./install.sh

# Install specific configuration sets
CONFIG_FILES="shared/shell shared/git" ./install.sh
```

## Architecture

### Tool Management

- All tools are defined in YAML files in the `_configs/` directory
- The default configuration is `_configs/tools.yaml`
- You can use custom configurations: `./install.sh -c devtools` or `CONFIG_FILES="devtools" ./install.sh`
- The `install.sh` script reads the specified YAML file and installs tools using the appropriate package manager
- Each tool has a `check_command` to verify if it's already installed (skip if present)

### Configuration Structure

The repository uses a layered configuration approach:

- **`_configs/shared/`** - Cross-platform tools (shell, git, search, file-tools, data-tools, network, neovim)
- **`_configs/host/`** - Host-specific configurations (common, personal, work, manual-check)
- **`_configs/focus/`** - Development focus areas (vscode, python, rust, typescript, kubernetes, ai, etc.)
- **Stow directories** - Each application has its own directory (e.g., `zsh/`, `git/`, `nvim/`)
- GNU Stow symlinks these directories to `$HOME`
- Configurations dynamically check for installed tools before loading features

### Makefile Configuration Sets

The Makefile defines convenient configuration combinations:

```makefile
SHARED_CONFIGS = shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim
COMMON_CONFIGS = $(SHARED_CONFIGS) + host/common
PERSONAL_CONFIGS = $(SHARED_CONFIGS) + host/common + host/personal + host/manual-check + focus/vscode
```

This allows simple commands like `make personal stow` to install entire configuration sets.

### Package Manager Priority

1. **brew** - Primary for macOS (packages, casks, taps)
2. **arkade** - CLI tools and Kubernetes apps
3. **uv** - Python tools
4. **cargo** - Rust binaries
5. **apt** - Ubuntu/Debian systems
6. **code** - VSCode extensions (supports `code`, `cursor`, `vscodium` via `VSCODE_CLI` env var)
7. **mas** - Mac App Store applications (requires signing into App Store first)

### Configuration Files

The configuration directory is flexible and can be customized:

1. **Default location**: `_configs/` directory in the repository
2. **Environment variable**: Set `CONFIG_DIR` to specify a custom directory
3. **Command-line option**: Use `-c` or `--config-dir` to override

Configuration files can include:

- `tools.yaml` - Default configuration with all available tools
- `devtools.yaml` - Development tools only (e.g., editors, linters, git tools)
- `productivity.yaml` - Productivity apps (e.g., task managers, note-taking)
- `work.yaml` - Work-specific tools
- `personal.yaml` - Personal machine setup

Example usage:

```bash
# Install default tools
./install.sh

# Install development tools only
./install.sh -c devtools

# Use configuration from current directory
CONFIG_DIR=./ ./install.sh -c personal

# Use external configuration directory
./install.sh --config-dir ~/my-configs -c work

# Use absolute path to config directory
./install.sh --config-dir /path/to/configs -c devtools

# Install with specific options
./install.sh -s -v -c work
```

The script searches for configuration files in this order:

1. If the YAML file path is absolute, use it directly
2. If CONFIG_DIR is absolute, look in `CONFIG_DIR/file.yaml`
3. If CONFIG_DIR is relative:
   - Check `./CONFIG_DIR/file.yaml` (relative to current directory)
   - Check `SCRIPT_DIR/CONFIG_DIR/file.yaml` (relative to install.sh location)
   - For backward compatibility with default config dir, also check `SCRIPT_DIR/file.yaml`

### Key Design Principles

- **Idempotent**: Running multiple times produces the same result
- **Cross-platform**: Works on macOS (primary) and Ubuntu
- **No hard dependencies**: Gracefully skips unavailable package managers
- **Modular**: Each tool/config can be managed independently
- **Fix Properly, Never Suppress**: NEVER fix errors by suppressing warnings or error messages. Always fix the root cause. If something is broken, diagnose and repair it correctly, or remove the problematic component entirely if it cannot be fixed properly.

## Working with the Codebase

### Adding a New Tool

1. Edit the appropriate YAML file in `_configs/` (or create a new one)
2. Add the tool definition with appropriate installer and check_command
3. Run `./install.sh -d -c [config]` to preview
4. Run `./install.sh -c [config]` to install

### Adding a New Configuration

1. Create a new directory for the application
2. Place configuration files in the correct structure (as they should appear in `$HOME`)
3. Add the directory to the stow list in `install.sh`
4. Run `./install.sh -s` to stow

### Modifying Existing Configurations

- Edit files directly in their respective directories
- Changes take effect immediately due to symlinks
- No need to re-stow unless adding new files

### Testing Changes

- Use `./install.sh -d` for dry runs
- The script provides detailed output about what would be done
- Force mode (`-f`) can adopt existing files if conflicts occur

### Running Tests

The repository includes comprehensive BATS test suites:

```bash
# Run all tests
./_test/run_tests.sh

# Run specific test suites
./_test/run_install_tests.sh        # install.sh tests only
./_test/run_macos_tests.sh          # macOS configuration tests only

# Run specific test file
cd _test && bats install.bats
cd _test && bats macos.bats
cd _test && bats makefile.bats
cd _test && bats 1password.bats
cd _test && bats bootstrap.bats

# Run with filter for specific test
cd _test && bats install.bats --filter "command_exists"
cd _test && bats macos.bats --filter "dock app management"

# Shellcheck all scripts
./_test/shellcheck.sh
```

Test coverage includes:

- **install.bats** - Core installation script functions and package manager handling
- **macos.bats** - macOS system configuration and dock management
- **makefile.bats** - Makefile target execution
- **1password.bats** - 1Password SSH and Git config integration
- **bootstrap.bats** - Fresh installation bootstrap process
- **configs.bats** - YAML configuration validation
- **manual.bats** - Manual installation checking
- **mas.bats** - Mac App Store integration

The test suite uses mocking to simulate all external commands (brew, apt, cargo, defaults, etc.) without requiring actual installations.

## Implementation Details

### Key Functions in install.sh

- **command_exists()** - Uses `type` (not `command -v`) to check if a command exists. This allows for easier mocking in tests.
- **get_available_managers()** - Returns available package managers to stdout, sends info messages to stderr
- **check_requirements()** - Verifies yq and which are installed
- **is_tool_installed()** - Runs the check_command for each tool to verify installation
- **install_tool()** - Handles installation based on manager and type
- **main()** - Orchestrates the installation process, handles empty lines in command output
  - Resolves YAML file path: checks current dir, then `_configs/`, then script directory
  - Supports custom configuration files passed as arguments

### Error Handling

- The script uses `set -euo pipefail` for strict error handling
- Functions return error codes rather than exiting (allows proper testing)
- Empty lines in command output are filtered to prevent processing empty entries

### Testing Approach

- Tests override the `type` builtin to control command existence checks
- Mock commands are placed in `$MOCK_BIN_DIR` which is prepended to PATH
- Integration tests use simplified yq mocks to control test scenarios
- BATS captures both stdout and stderr in `$output`

### Common Pitfalls

- When `yq` returns empty results, `while read` loops may still process one empty line
- The `<<<` operator always provides at least one line of input, even if empty
- Info messages must be carefully managed to not interfere with function return values
- Brew tap names (like `FelixKratz/formulae`) contain `/` and need quotes in yq queries: `.tools."FelixKratz/formulae".manager`
- Functions that check system state must handle `set -e` properly to avoid early exit on expected failures

### Handling errexit in Functions

The script uses `set -euo pipefail` for safety, but some functions need to tolerate command failures:

```bash
get_available_managers() {
  # Save and disable errexit for this function
  local old_errexit
  old_errexit=$(set +o | grep errexit)
  set +e

  # Function body that may have failing commands
  # e.g., checking if commands exist

  # Restore errexit before returning
  eval "$old_errexit"
  return 0
}
```

This pattern is critical for:

- Functions that check if commands exist (which return non-zero when not found)
- Information gathering functions that shouldn't fail the entire script
- Test compatibility where mocked commands might not exist

## macOS Configuration Script

The `_macos/macos.sh` script provides automated macOS system configuration management.

### Usage

```bash
# Show current system settings (default mode)
./_macos/macos.sh

# Apply configuration from YAML file
./_macos/macos.sh personal.yaml

# Dry run to preview changes
./_macos/macos.sh -d personal.yaml

# The script automatically looks in its own directory for YAML files
cd /anywhere && /path/to/_macos/macos.sh personal.yaml  # Works!
```

### Dock Management

The script can manage dock applications with intelligent duplicate prevention:

```yaml
dock:
  manage_apps: true
  clear_dock_first: false # Set to true to start fresh
  apps:
    - "/Applications/Visual Studio Code.app"
    - "/Applications/Brave Browser.app"
```

**Important Notes:**

- Running multiple times with `clear_dock_first: false` will NOT create duplicates
- The script checks existing dock apps before adding (URL decoding handles spaces in names)
- Finder is ALWAYS in the dock by default - don't add it to your apps list
- Some system apps have non-standard paths (e.g., Finder is in `/System/Library/CoreServices/`)

### Implementation

#### Arithmetic Operations with errexit

When using `set -e`, arithmetic operations that evaluate to 0 will cause the script to exit:

```bash
# WRONG - will exit when count is 0
((count++))

# CORRECT - won't exit
((count++)) || true
```

#### Dock App Detection

The script handles URL-encoded paths from macOS defaults:

```bash
# Dock apps are stored with URL encoding and file:// prefix
# The script decodes these for accurate duplicate detection
defaults read com.apple.dock persistent-apps | \
  grep -o '"_CFURLString" = "[^"]*"' | \
  sed 's/"_CFURLString" = "//; s/"$//; s|^file://||; s|/$||' | \
  python3 -c "import sys, urllib.parse; [print(urllib.parse.unquote(line.strip())) for line in sys.stdin]"
```

### Testing macOS Script

The macOS script has its own comprehensive BATS test suite:

```bash
# Run all macOS tests
cd _test && bats macos.bats

# Run specific test
bats macos.bats --filter "dock app management"
```

Key testing patterns:

- Mock `defaults` command to simulate system state
- Mock `python3` for URL decoding in tests
- Test duplicate prevention with pre-existing dock apps
- Verify dry-run mode doesn't modify system

### Common Issues and Solutions

1. **"App not found: /Applications/Finder.app"**

   - Finder is in `/System/Library/CoreServices/Finder.app`
   - Better solution: Remove Finder from your apps list (it's always there)

2. **Duplicate dock items**

   - Ensure you're using the latest version with URL decoding
   - The script now properly detects apps with spaces in names

3. **Script exits unexpectedly**
   - Check for arithmetic operations without `|| true`
   - Ensure all `grep` commands that might not match use `|| echo ""`

## 1Password Integration

The repository includes secure credential and configuration management via 1Password CLI.

### SSH Configuration Management

```bash
# Safe mode (default) - downloads SSH config + public keys only
# Private keys remain in 1Password, uses 1Password SSH Agent
./setup-ssh-from-1password.sh

# Dry run to check what's available
./setup-ssh-from-1password.sh --dry-run

# Unsafe mode - downloads private keys (requires confirmation)
# Only use when 1Password SSH Agent isn't available
./setup-ssh-from-1password.sh --unsafe
```

**Security Model:**

- Default mode never downloads private keys to disk
- Uses 1Password SSH Agent for authentication
- Only downloads SSH config and public keys for reference
- Unsafe mode should only be used in restricted environments

### Git Configuration Management

```bash
# Download work-specific Git config from 1Password
./setup-gitconfig-from-1password.sh

# Dry run to check availability
./setup-gitconfig-from-1password.sh --dry-run
```

This allows storing work-specific Git configuration (email, GitHub Enterprise URLs) in 1Password and automatically applying it to `~/Developer/work/.gitconfig_include`.

### 1Password Item Naming Convention

The scripts expect specific item names in 1Password:

- **SSH Keys:** `github_personal_authentication`, `github_personal_signing`, `aws_work_2024_client_1`, etc.
- **SSH Config:** Secure Note named `SSH Config`
- **Git Config:** Secure Note named `work .gitconfig_include`
- **AWS Credentials:** API Credential items mapped in `aws/.aws/aws-1password` script

See README.md "Setting Up 1Password Items" section for detailed setup instructions.

## Complete Setup Workflows

### Fresh Personal Mac

```bash
# 1. Bootstrap (installs Homebrew, yq, stow)
./bootstrap.sh

# 2. Full personal setup (or run ./setup-personal-mac.sh for all at once)
make personal install

# 3. Apply macOS settings
./_macos/macos.sh personal.yaml

# 4. Stow configurations
make personal stow

# 5. Set up SSH from 1Password (requires 1Password CLI)
./setup-ssh-from-1password.sh
```

### Fresh Work Mac

```bash
# Complete work setup (includes SSH and Git config from 1Password)
./setup-work-mac.sh
```

### Adding New Tools

```bash
# 1. Edit appropriate YAML in _configs/
vim _configs/shared/shell.yaml

# 2. Preview changes
./install.sh -d

# 3. Install
./install.sh

# 4. Test
cd _test && bats install.bats
```
