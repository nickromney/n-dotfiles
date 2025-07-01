# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository designed for cross-platform configuration management. It uses GNU Stow for symlink management and supports multiple package managers (brew, arkade, uv, cargo, apt). The design is modular and idempotent.

## Key Commands

```bash
# Install packages and stow configurations
./install.sh -s

# Dry run mode (preview changes without making them)
./install.sh -d -s

# Force mode (adopt existing files during stow)
./install.sh -s -f

# Verbose output
./install.sh -v

# Install only (no stowing)
./install.sh
```

## Architecture

### Tool Management

- All tools are defined in `tools.yaml` with installation methods and verification commands
- The `install.sh` script reads this YAML file and installs tools using the appropriate package manager
- Each tool has a `check_command` to verify if it's already installed (skip if present)

### Configuration Structure

- Each application has its own directory (e.g., `zsh/`, `git/`, `nvim/`)
- GNU Stow symlinks these directories to `$HOME`
- Configurations dynamically check for installed tools before loading features

### Package Manager Priority

1. **brew** - Primary for macOS (packages, casks, taps)
2. **arkade** - CLI tools and Kubernetes apps
3. **uv** - Python tools
4. **cargo** - Rust binaries
5. **apt** - Ubuntu/Debian systems

### Key Design Principles

- **Idempotent**: Running multiple times produces the same result
- **Cross-platform**: Works on macOS (primary) and Ubuntu
- **No hard dependencies**: Gracefully skips unavailable package managers
- **Modular**: Each tool/config can be managed independently

## Working with the Codebase

### Adding a New Tool

1. Edit `tools.yaml` and add the tool definition with appropriate installer and check_command
2. Run `./install.sh -d` to preview
3. Run `./install.sh` to install

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
# Run all tests (macOS only)
./_test/run_tests.sh

# Run install tests only (cross-platform)
./_test/run_install_tests.sh

# Run specific tests
cd _test && bats install.bats --filter "command_exists"
```

**Platform-specific testing:**
- **Ubuntu/Linux**: Only runs `install.bats` (cross-platform installation tests)
- **macOS**: Runs both `install.bats` and `macos.bats`

The test suite uses mocking to simulate all external commands (brew, apt, cargo, etc.) without requiring actual installations.

## Implementation Details

### Key Functions in install.sh

- **command_exists()** - Uses `type` (not `command -v`) to check if a command exists. This allows for easier mocking in tests.
- **get_available_managers()** - Returns available package managers to stdout, sends info messages to stderr
- **check_requirements()** - Verifies yq and which are installed
- **is_tool_installed()** - Runs the check_command for each tool to verify installation
- **install_tool()** - Handles installation based on manager and type
- **main()** - Orchestrates the installation process, handles empty lines in command output

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
  clear_dock_first: false  # Set to true to start fresh
  apps:
    - "/Applications/Visual Studio Code.app"
    - "/Applications/Brave Browser.app"
```

**Important Notes:**
- Running multiple times with `clear_dock_first: false` will NOT create duplicates
- The script checks existing dock apps before adding (URL decoding handles spaces in names)
- Finder is ALWAYS in the dock by default - don't add it to your apps list
- Some system apps have non-standard paths (e.g., Finder is in `/System/Library/CoreServices/`)

### Implementation Details

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
