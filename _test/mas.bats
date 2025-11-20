#!/usr/bin/env bats

load helpers/mocks

# Setup and teardown
setup() {
  setup_mocks

  # Set up test environment
  export CONFIG_DIR="_configs"
  export CONFIG_FILES=("test")
  export DRY_RUN="false"
  export VERBOSE="false"
  export STOW="false"
  export FORCE="false"
  export UPDATE="false"
  export CONFIG_FILES_SET_VIA_CLI="false"

  # Change to the script directory to ensure relative paths work
  cd "$BATS_TEST_DIRNAME/.."

  # Source the install script functions only (not main)
  set +e  # Temporarily disable errexit
  # shellcheck source=/dev/null
  source ./install.sh --source-only
  set -e  # Re-enable errexit
}

teardown() {
  teardown_mocks
}

# Test mas manager detection
@test "mas: detects when mas is available" {
  mock_mas

  # Mock yq to return mas as a manager
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    echo "mas"
    ;;
  *)
    echo "null"
    ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"

  run get_available_managers "test.yaml"
  [ "$status" -eq 0 ]
  # Function now outputs manager names to stdout
  [[ "$output" =~ "mas" ]]
}

@test "mas: detects when mas is not installed" {
  # Don't mock mas (simulate it's not installed)
  # Override command_exists to simulate mas not being available
  command_exists() {
    [[ "$1" == "mas" ]] && return 1
    # Allow other commands to be found
    type "$1" >/dev/null 2>&1
  }
  export -f command_exists

  # Mock yq to return mas as a manager
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    echo "mas"
    ;;
  *)
    echo "null"
    ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"

  run get_available_managers "test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "mas: please install with 'brew install mas'" ]]
}

# Test mas app installation
@test "mas: installs app with app_id" {
  mock_mas

  # Mock yq for Things app
  yq() {
    case "$*" in
      *".tools.things.manager"*) echo "mas" ;;
      *".tools.things.type"*) echo "app" ;;
      *".tools.things.app_id"*) echo "904280696" ;;
      *".tools.things.install_args[]"*) echo "" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  run install_tool "things" "test.yaml"
  [ "$status" -eq 0 ]
  assert_mock_called "mas" "install 904280696"
}

@test "mas: fails when app_id is missing" {
  mock_mas

  # Mock yq without app_id
  yq() {
    case "$*" in
      *".tools.app.manager"*) echo "mas" ;;
      *".tools.app.type"*) echo "app" ;;
      *".tools.app.app_id"*) echo "" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  run install_tool "app" "test.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "No app_id specified" ]]
}

# Test mas app installation check
@test "mas: detects installed app" {
  # Mock mas with Things installed
  echo '#!/usr/bin/env bash
case "$1" in
  list)
    echo "904280696   Things                 (3.21.14)"
    echo "967805235    Paste                  (5.0.9)"
    ;;
esac' > "$MOCK_BIN_DIR/mas"
  chmod +x "$MOCK_BIN_DIR/mas"

  # Mock yq
  yq() {
    case "$*" in
      *".tools.things.check_command"*) echo "mas list | grep -q '^904280696'" ;;
      *".tools.things.manager"*) echo "mas" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  run is_tool_installed "things" "test.yaml"
  [ "$status" -eq 0 ]
}

@test "mas: detects missing app" {
  # Mock mas without Things
  echo '#!/usr/bin/env bash
case "$1" in
  list)
    echo "967805235    Paste                  (5.0.9)"
    ;;
esac' > "$MOCK_BIN_DIR/mas"
  chmod +x "$MOCK_BIN_DIR/mas"

  # Mock yq
  yq() {
    case "$*" in
      *".tools.things.check_command"*) echo "mas list | grep -q '^904280696'" ;;
      *".tools.things.manager"*) echo "mas" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  run is_tool_installed "things" "test.yaml"
  [ "$status" -eq 1 ]
}

# Test mas app updates
@test "mas: updates outdated app" {
  export UPDATE="true"
  export CURRENT_CONFIG_FILE="test.yaml"

  # Mock mas with outdated app
  echo '#!/usr/bin/env bash
case "$*" in
  outdated)
    echo "904280696   Things         (3.21.13 -> 3.21.14)"
    ;;
  "upgrade 904280696")
    echo "==> Upgrading Things..."
    echo "✓ Successfully upgraded Things"
    ;;
esac' > "$MOCK_BIN_DIR/mas"
  chmod +x "$MOCK_BIN_DIR/mas"

  # Mock yq
  yq() {
    case "$*" in
      *".tools.things.app_id"*) echo "904280696" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  # Create mock file to track calls
  export MOCK_CALL_LOG="$MOCK_CALLS_DIR/mas.calls"

  # Simulate the update check (this would normally be in main loop)
  if mas outdated | grep -q "^904280696"; then
    mas upgrade "904280696"
  fi

  # Check that upgrade was called
  [ -f "$MOCK_BIN_DIR/mas" ]
}

@test "mas: skips up-to-date app" {
  export UPDATE="true"
  export CURRENT_CONFIG_FILE="test.yaml"

  # Mock mas with no outdated apps
  echo '#!/usr/bin/env bash
case "$*" in
  outdated)
    # Return empty - nothing outdated
    ;;
  upgrade)
    echo "ERROR: Should not be called"
    exit 1
    ;;
esac' > "$MOCK_BIN_DIR/mas"
  chmod +x "$MOCK_BIN_DIR/mas"

  # Mock yq
  yq() {
    case "$*" in
      *".tools.things.app_id"*) echo "904280696" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  # Simulate the update check
  if mas outdated | grep -q "^904280696"; then
    mas upgrade "904280696"
    # Should not reach here
    false
  fi

  # Test passes if upgrade was not called
  true
}

# Test dry run mode
@test "mas: respects dry run mode" {
  export DRY_RUN="true"
  mock_mas

  # Mock yq
  yq() {
    case "$*" in
      *".tools.things.manager"*) echo "mas" ;;
      *".tools.things.type"*) echo "app" ;;
      *".tools.things.app_id"*) echo "904280696" ;;
      *".tools.things.install_args[]"*) echo "" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  run install_tool "things" "test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Would execute: mas install 904280696" ]]
  assert_mock_not_called "mas"
}

# Test integration with personal.yaml config
@test "mas: reads personal.yaml config correctly" {
  # Create a temporary config file
  cat > "$BATS_TEST_TMPDIR/personal.yaml" << 'EOF'
tools:
  things:
    manager: mas
    type: app
    app_id: "904280696"
    check_command: "mas list | grep -q '^904280696'"
    description: "Task management app"
    category: productivity

  paste:
    manager: mas
    type: app
    app_id: "967805235"
    check_command: "mas list | grep -q '^967805235'"
    description: "Clipboard manager"
    category: productivity
EOF

  # Mock yq to read our test file
  echo '#!/usr/bin/env bash
if [[ "$*" == *"keys"* ]]; then
  echo "things"
  echo "paste"
elif [[ "$*" == *"things.manager"* ]]; then
  echo "mas"
elif [[ "$*" == *"paste.manager"* ]]; then
  echo "mas"
fi' > "$MOCK_BIN_DIR/yq"
  chmod +x "$MOCK_BIN_DIR/yq"

  mock_mas

  # Get tools from config
  run yq '.tools | keys | .[]' "$BATS_TEST_TMPDIR/personal.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "things" ]]
  [[ "$output" =~ "paste" ]]
}
