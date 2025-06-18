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

The repository includes a comprehensive BATS test suite for `install.sh`:

```bash
# Run all tests
./_test/run_tests.sh

# Run specific tests
cd _test && bats install.bats --filter "command_exists"
```

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
