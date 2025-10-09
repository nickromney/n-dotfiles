#!/usr/bin/env bats

setup() {
  # Set test environment
  export BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-/tmp/bats-test-$$}"
  mkdir -p "$BATS_TEST_TMPDIR"

  # Save original directory
  ORIG_DIR="$PWD"

  # Copy the setup script
  cp "${BATS_TEST_DIRNAME}/../setup-work-mac.sh" "$BATS_TEST_TMPDIR/setup-work-mac.sh"
  chmod +x "$BATS_TEST_TMPDIR/setup-work-mac.sh"

  # Create mock directories in temp dir
  mkdir -p "$BATS_TEST_TMPDIR/mocks"
  mkdir -p "$BATS_TEST_TMPDIR/_configs/host"
  mkdir -p "$BATS_TEST_TMPDIR/_macos"

  # Set PATH to use mocks
  export PATH="$BATS_TEST_TMPDIR/mocks:$PATH"

  # Change to test directory - this is where script will run
  cd "$BATS_TEST_TMPDIR"
}

teardown() {
  cd "$ORIG_DIR"
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

@test "setup-work-mac: fails on non-macOS" {
  export UNAME_OUTPUT="Linux"
  create_mock "uname" 0 "$UNAME_OUTPUT"

  run ./setup-work-mac.sh
  [ "$status" -eq 1 ]
  [[ "$output" =~ "This script is for macOS only" ]]
}

@test "setup-work-mac: runs bootstrap when tools missing" {
  skip "Complex integration test - command builtin cannot be mocked via PATH"
  create_mock "uname" 0 "Darwin"
  create_mock "command" 1  # Simulate tools not found

  # Create mock bootstrap
  cat > "./bootstrap.sh" << 'EOF'
#!/usr/bin/env bash
echo "Bootstrap executed"
exit 0
EOF
  chmod +x "./bootstrap.sh"

  # Create mock install.sh
  create_mock "./install.sh" 0 "Install executed"

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Bootstrap executed" ]]
}

@test "setup-work-mac: skips bootstrap when tools present" {
  skip "Complex integration test - command builtin cannot be mocked via PATH"
  create_mock "uname" 0 "Darwin"
  create_mock "command" 0  # All tools found
  create_mock "brew" 0
  create_mock "yq" 0
  create_mock "stow" 0
  create_mock "./install.sh" 0

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Essential tools already installed" ]]
}

@test "setup-work-mac: installs shared and common packages" {
  skip "Complex integration test - command builtin cannot be mocked via PATH"
  create_mock "uname" 0 "Darwin"
  create_mock "command" 0

  # Track install.sh calls
  cat > "./install.sh" << 'EOF'
#!/usr/bin/env bash
echo "install.sh called with: $*"
exit 0
EOF
  chmod +x "./install.sh"

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES=\"shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common\"" ]]
}

@test "setup-work-mac: installs work packages when config exists" {
  skip "Complex integration test - command builtin cannot be mocked via PATH"
  create_mock "uname" 0 "Darwin"
  create_mock "command" 0

  # Create work config
  touch "_configs/host/work.yaml"

  # Track install.sh calls
  cat > "./install.sh" << 'EOF'
#!/usr/bin/env bash
echo "install.sh called with: $*"
[[ "$*" == "-s" ]] && echo "Stowing configurations"
exit 0
EOF
  chmod +x "./install.sh"

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES=\"host/work\"" ]]
}

@test "setup-work-mac: skips work packages when config missing" {
  skip "Complex integration test - command builtin cannot be mocked via PATH"
  create_mock "uname" 0 "Darwin"
  create_mock "command" 0
  create_mock "./install.sh" 0

  # No work.yaml file

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No work-specific configuration found" ]]
}

@test "setup-work-mac: applies macOS settings when config exists" {
  skip "Complex integration test - command builtin cannot be mocked via PATH"
  create_mock "uname" 0 "Darwin"
  create_mock "command" 0
  create_mock "./install.sh" 0

  # Create work macOS config
  touch "_macos/work.yaml"

  # Create mock macos.sh
  cat > "./_macos/macos.sh" << 'EOF'
#!/usr/bin/env bash
echo "macos.sh called with: $*"
exit 0
EOF
  chmod +x "./_macos/macos.sh"

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "macos.sh called with: work.yaml" ]]
}

@test "setup-work-mac: runs stow" {
  create_mock "uname" 0 "Darwin"
  create_mock "command" 0

  # Track install.sh calls
  cat > "./install.sh" << 'EOF'
#!/usr/bin/env bash
[[ "$1" == "-s" ]] && echo "Stow executed"
exit 0
EOF
  chmod +x "./install.sh"

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Stow executed" ]]
}

@test "setup-work-mac: installs VSCode extensions when code available" {
  create_mock "uname" 0 "Darwin"
  create_mock "command" 0
  create_mock "code" 0

  # Track install.sh calls
  cat > "./install.sh" << 'EOF'
#!/usr/bin/env bash
[[ "$*" =~ "focus/vscode" ]] && echo "VSCode extensions installed"
exit 0
EOF
  chmod +x "./install.sh"

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VSCode extensions installed" ]]
}

@test "setup-work-mac: skips VSCode when not available" {
  skip "Complex integration test - command builtin cannot be mocked via PATH"
  create_mock "uname" 0 "Darwin"

  # Make command return failure for 'code'
  cat > "$BATS_TEST_TMPDIR/mocks/command" << 'EOF'
#!/usr/bin/env bash
[[ "$2" == "code" ]] && exit 1
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/mocks/command"

  create_mock "./install.sh" 0

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VSCode not found, skipping extensions" ]]
}

@test "setup-work-mac: shows next steps" {
  skip "Complex integration test - command builtin cannot be mocked via PATH"
  create_mock "uname" 0 "Darwin"
  create_mock "command" 0
  create_mock "./install.sh" 0

  run ./setup-work-mac.sh
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Setup Complete!" ]]
  [[ "$output" =~ "Next steps:" ]]
  [[ "$output" =~ "git config" ]]
}
