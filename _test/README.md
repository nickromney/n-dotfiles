# Test Suite

This directory contains the test suite for the dotfiles repository:
BATS suites for the setup entrypoints (`bootstrap.sh`, `stow.sh`,
`setup-personal-mac.sh`, the `Makefile`) and for `_macos/macos.sh`,
plus shellcheck and Lima-based POSIX smoke tests.

## Prerequisites

Install BATS:

```bash
# macOS
brew install bats-core

# Ubuntu/Debian
sudo apt-get install bats

# Or from source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local
```

## Running Tests

```bash
# Run all tests
./_test/run_tests.sh

# Run macOS configuration tests only
./_test/run_macos_tests.sh

# Or run a single suite directly with bats
bats _test/makefile.bats

# Run specific test
bats _test/makefile.bats --filter "brewfile-install"

# Verbose output for debugging
bats _test/makefile.bats --verbose-run

# Lint shell scripts
./_test/shellcheck.sh
```

## Test Structure

- `bootstrap.bats` - CLI contract and dry-run behavior of `bootstrap.sh`
- `cli-contracts.bats` - `--help`/`--dry-run` contracts for user-facing scripts, including `stow.sh`
- `makefile.bats` - Makefile targets (install, stow, mise-install, update, configure)
- `setup-personal-mac.bats` - Orchestration flow of `setup-personal-mac.sh`
- `macos.bats` - macOS defaults logic (`_macos/macos.sh`)
- `shell-configs.bats` - bash/zsh startup behavior and PATH ordering
- `1password.bats`, `nushell.bats`, `harness-guides.bats` - focused suites
- `helpers/mocks.bash` - Mock command utilities and helper functions
- `lima/` - Ubuntu VM smoke tests for the POSIX path (Brewfile.posix + stow.sh + mise)

## Mock System

The test suite uses a mocking system to simulate external commands:

### Basic Mocking

```bash
# Create a simple mock
mock_command "tool_name" exit_code "optional_output"

# Create a mock with custom behavior
mock_command_with_script "tool_name" 'custom bash script'
```

### Assertions

```bash
# Check if mock was called
assert_mock_called "command" "expected arguments"

# Check if mock was NOT called
assert_mock_not_called "command"

# Get call count
count=$(get_mock_call_count "command")
```

## Adding New Tests

1. Create or update mocks in `helpers/mocks.bash`
2. Add test cases to the relevant `.bats` suite:

```bash
@test "description of what you're testing" {
  # Setup mocks
  mock_command "some_tool"

  # Run function
  run function_to_test "arguments"

  # Assert results
  [ "$status" -eq 0 ]
  [[ "$output" =~ "expected output" ]]
  assert_mock_called "some_tool" "expected args"
}
```

## Debugging Tests

Run with verbose output:

```bash
bats _test/makefile.bats --verbose-run
```

Use `echo` statements in tests (output only shown on failure):

```bash
@test "debugging example" {
  echo "Debug info: $variable" >&3
  # ... rest of test
}
```
