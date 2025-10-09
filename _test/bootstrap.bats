#!/usr/bin/env bats

setup() {
  # Set test environment
  export BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-/tmp/bats-test-$$}"
  mkdir -p "$BATS_TEST_TMPDIR"

  # Create a mock bootstrap script for testing
  cp "${BATS_TEST_DIRNAME}/../bootstrap.sh" "$BATS_TEST_TMPDIR/bootstrap.sh"
  chmod +x "$BATS_TEST_TMPDIR/bootstrap.sh"

  # Mock commands
  export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

  # Set non-interactive mode to skip prompts
  export NON_INTERACTIVE=1
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR"
}

# Helper to create mock commands
create_mock() {
  local cmd="$1"
  local exit_code="${2:-0}"
  local output="${3:-}"

  cat > "$BATS_TEST_TMPDIR/mocks/$cmd" << EOF
#!/usr/bin/env bash
[[ -n "$output" ]] && echo "$output"
exit $exit_code
EOF
  chmod +x "$BATS_TEST_TMPDIR/mocks/$cmd"
}

@test "bootstrap: fails on non-macOS systems" {
  export OSTYPE="linux-gnu"
  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "This bootstrap script is designed for macOS only" ]]
}

@test "bootstrap: creates Developer directory structure" {
  skip "Complex integration test - requires full environment"
  export OSTYPE="darwin"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$BATS_TEST_TMPDIR/mocks"

  # Mock all required commands
  create_mock "brew" 0
  create_mock "curl" 0
  create_mock "nvm" 0

  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ -d "$HOME/Developer/personal" ]
}

@test "bootstrap: installs Homebrew when not present" {
  skip "Complex integration test - requires full environment"
  export OSTYPE="darwin"
  mkdir -p "$BATS_TEST_TMPDIR/mocks"

  # Create a mock that fails first (command not found), then succeeds
  cat > "$BATS_TEST_TMPDIR/mocks/command" << 'EOF'
#!/usr/bin/env bash
if [[ "$2" == "brew" ]] && [[ ! -f "$BATS_TEST_TMPDIR/.brew_installed" ]]; then
  exit 1
else
  exit 0
fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/mocks/command"

  # Mock the brew installation
  cat > "$BATS_TEST_TMPDIR/mocks/bash" << 'EOF'
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/.brew_installed"
echo "Homebrew installed"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/mocks/bash"

  create_mock "curl" 0 "install script"
  create_mock "brew" 0
  create_mock "nvm" 0

  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Installing Homebrew" ]]
}

@test "bootstrap: skips Homebrew when already installed" {
  skip "Complex integration test - requires full environment"
  export OSTYPE="darwin"
  mkdir -p "$BATS_TEST_TMPDIR/mocks"

  create_mock "command" 0
  create_mock "brew" 0
  create_mock "nvm" 0

  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Homebrew already installed" ]]
}

@test "bootstrap: installs essential tools" {
  skip "Complex integration test - requires full environment"
  export OSTYPE="darwin"
  mkdir -p "$BATS_TEST_TMPDIR/mocks"

  create_mock "command" 0

  # Track brew install calls
  cat > "$BATS_TEST_TMPDIR/mocks/brew" << 'EOF'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/brew_calls.txt"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/mocks/brew"

  create_mock "nvm" 0

  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 0 ]

  # Check that essential tools were installed
  grep -q "install yq" "$BATS_TEST_TMPDIR/brew_calls.txt"
  grep -q "install stow" "$BATS_TEST_TMPDIR/brew_calls.txt"
  grep -q "install nvm" "$BATS_TEST_TMPDIR/brew_calls.txt"
}

@test "bootstrap: installs Node.js via nvm" {
  skip "Complex integration test - requires full environment"
  export OSTYPE="darwin"
  mkdir -p "$BATS_TEST_TMPDIR/mocks"

  create_mock "command" 0
  create_mock "brew" 0

  # Track nvm calls
  cat > "$BATS_TEST_TMPDIR/mocks/nvm" << 'EOF'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/nvm_calls.txt"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/mocks/nvm"

  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 0 ]

  # Check nvm commands
  grep -q "install --lts" "$BATS_TEST_TMPDIR/nvm_calls.txt"
  grep -q "use --lts" "$BATS_TEST_TMPDIR/nvm_calls.txt"
  grep -q "alias default node" "$BATS_TEST_TMPDIR/nvm_calls.txt"
}

@test "bootstrap: creates .nvm directory" {
  skip "Complex integration test - requires full environment"
  export OSTYPE="darwin"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$BATS_TEST_TMPDIR/mocks"

  create_mock "command" 0
  create_mock "brew" 0
  create_mock "nvm" 0

  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.nvm" ]
}

@test "bootstrap: skips 1Password in non-interactive mode" {
  skip "Complex integration test - requires full environment"
  export OSTYPE="darwin"
  export NON_INTERACTIVE=1
  mkdir -p "$BATS_TEST_TMPDIR/mocks"

  create_mock "command" 0
  create_mock "brew" 0
  create_mock "nvm" 0

  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Skipping 1Password installation" ]]
  [[ ! "$output" =~ "Do you use 1Password" ]]
}

@test "bootstrap: shows next steps" {
  skip "Complex integration test - requires full environment"
  export OSTYPE="darwin"
  mkdir -p "$BATS_TEST_TMPDIR/mocks"

  create_mock "command" 0
  create_mock "brew" 0
  create_mock "nvm" 0

  run "$BATS_TEST_TMPDIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Next steps:" ]]
  [[ "$output" =~ "./install.sh -d" ]]
  [[ "$output" =~ "make focus-vscode" ]]
  [[ "$output" =~ "make focus-neovim" ]]
}
