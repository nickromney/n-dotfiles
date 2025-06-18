# Install Script Tests

This directory contains BATS (Bash Automated Testing System) tests for the `install.sh` script.

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
./test/run_tests.sh

# Or run directly with bats
cd test
bats install.bats

# Run specific test
bats install.bats --filter "command_exists"

# Verbose output for debugging
bats install.bats --verbose-run

# TAP format output
bats install.bats --tap
```

## Convenience Commands

```bash
# Run tests continuously on file changes (requires entr or nodemon)
find . -name "*.sh" -o -name "*.bats" -o -name "*.bash" | entr -c ./test/run_tests.sh

# Lint shell scripts (requires shellcheck)
shellcheck install.sh test/*.bats test/helpers/*.bash

# Format shell scripts (requires shfmt)
shfmt -w install.sh test/*.bats test/helpers/*.bash

# Test installation modes
./install.sh -d -v          # Dry run with verbose output
./install.sh -v             # Install tools only
./install.sh -s -v          # Install and stow
./install.sh -s -f -v       # Force stow (adopt existing files)
```

## Test Structure

- `install.bats` - Main test file containing all test cases
- `helpers/mocks.bash` - Mock command utilities and helper functions
- Uses the actual `tools.yaml` from the repository root

## Mock System

The test suite uses a comprehensive mocking system to simulate external commands:

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

### Pre-built Package Manager Mocks

- `mock_brew` - Simulates Homebrew commands
- `mock_apt_get` - Simulates apt-get commands
- `mock_arkade` - Simulates arkade commands
- `mock_cargo` - Simulates cargo commands
- `mock_uv` - Simulates uv commands
- `mock_stow` - Simulates GNU stow
- `mock_yq` - Simulates yq with test data

## Test Coverage

The test suite covers:

1. **Utility Functions**

   - `command_exists` - Command detection
   - `is_root` - Root user detection
   - `is_tool_installed` - Tool installation verification
   - `can_install_tool` - Manager availability check

2. **Core Functions**

   - `check_requirements` - Required command validation
   - `get_available_managers` - Package manager detection
   - `install_tool` - Tool installation for all managers
   - `run_stow` - GNU Stow integration

3. **Integration Tests**
   - Main function behavior
   - Dry run mode
   - Force mode
   - Verbose output
   - Error handling

## Adding New Tests

1. Add test data to `fixtures/tools.yaml` if needed
2. Create or update mocks in `helpers/mocks.bash`
3. Add test cases to `install.bats`:

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
bats install.bats --verbose-run
```

Use `echo` statements in tests (output only shown on failure):

```bash
@test "debugging example" {
  echo "Debug info: $variable" >&3
  # ... rest of test
}
```
