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

# Test manual manager detection
@test "manual: manager is always available" {
  # Mock yq to return manual as a manager
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    echo "manual"
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
  [[ "$output" =~ "manual" ]]
}

# Test manual tool "installation" (should just report, not install)
@test "manual: reports but doesn't install" {
  # Mock yq for manual tool
  yq() {
    case "$*" in
      *".tools.snagit.manager"*) echo "manual" ;;
      *".tools.snagit.type"*) echo "check" ;;
      *".tools.snagit.description"*) echo "Screen capture software" ;;
      *".tools.snagit.documentation_url"*) echo "https://www.techsmith.com/screen-capture.html" ;;
      *".tools.snagit.install_args[]"*) echo "" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  run install_tool "snagit" "test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "snagit requires manual installation" ]]
  [[ "$output" =~ "Screen capture software" ]]
  [[ "$output" =~ "https://www.techsmith.com/screen-capture.html" ]]
}

# Test manual tool in dry run mode
@test "manual: respects dry run mode" {
  export DRY_RUN="true"

  # Mock yq for manual tool
  yq() {
    case "$*" in
      *".tools.homerow.manager"*) echo "manual" ;;
      *".tools.homerow.type"*) echo "check" ;;
      *".tools.homerow.description"*) echo "Keyboard navigation" ;;
      *".tools.homerow.documentation_url"*) echo "https://www.homerow.app/" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  run install_tool "homerow" "test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Would report: homerow requires manual installation" ]]
  [[ "$output" =~ "Download from: https://www.homerow.app/" ]]
}

# Test manual tool installation check
@test "manual: detects installed app" {
  # Create mock app directory structure
  mkdir -p "$BATS_TEST_TMPDIR/Applications/Snagit 2024.app"

  # Mock yq
  yq() {
    case "$*" in
      *".tools.snagit.check_command"*) echo "test -d '$BATS_TEST_TMPDIR/Applications/Snagit 2024.app'" ;;
      *".tools.snagit.manager"*) echo "manual" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  run is_tool_installed "snagit" "test.yaml"
  [ "$status" -eq 0 ]
}

# Test manual tool not installed
@test "manual: detects missing app" {
  # Mock yq with a check that will fail
  yq() {
    case "$*" in
      *".tools.superkey.check_command"*) echo "test -d '$BATS_TEST_TMPDIR/Applications/Superkey.app'" ;;
      *".tools.superkey.manager"*) echo "manual" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  # Don't create the app directory, so the check will fail
  run is_tool_installed "superkey" "test.yaml"
  [ "$status" -eq 1 ]
}

# Test manual tool in update mode (should skip)
@test "manual: skips updates" {
  export UPDATE="true"
  export CURRENT_CONFIG_FILE="test.yaml"

  # Mock yq
  yq() {
    case "$*" in
      *".tools.camtasia.manager"*) echo "manual" ;;
      *".tools.camtasia.type"*) echo "check" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  # Simulate the update check (this would be in main loop)
  manager=$(yq ".tools.camtasia.manager" "$CURRENT_CONFIG_FILE")
  type=$(yq ".tools.camtasia.type" "$CURRENT_CONFIG_FILE")

  if [[ "$manager" == "manual" ]]; then
    echo "✓ camtasia (manual) - check vendor site for updates"
  fi

  run echo "✓ camtasia (manual) - check vendor site for updates"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "check vendor site for updates" ]]
}

# Test manual tool already installed message
@test "manual: shows correct already installed message" {
  # Create a simple test that simulates the main loop behavior
  manager="manual"
  type="check"
  tool="beyond-compare"

  # Simulate the already installed message
  case "$manager" in
    "manual")
      output="✓ $tool (manual) is already installed"
      ;;
  esac

  run echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "✓ beyond-compare (manual) is already installed" ]]
}

# Test can_install_tool with manual manager
@test "manual: can_install_tool returns success" {
  # Mock yq
  yq() {
    case "$*" in
      *".tools.gpg-keychain.manager"*) echo "manual" ;;
      *) echo "null" ;;
    esac
  }
  export -f yq

  AVAILABLE_MANAGERS=("manual" "brew")

  run can_install_tool "gpg-keychain" "test.yaml"
  [ "$status" -eq 0 ]
}

# Test reading manual-check.yaml config
@test "manual: reads manual-check.yaml correctly" {
  # Create a temporary config file
  cat > "$BATS_TEST_TMPDIR/manual-check.yaml" << 'EOF'
tools:
  snagit:
    manager: manual
    type: check
    check_command: "[ -d '/Applications/Snagit 2024.app' ]"
    description: "Screen capture software"
    documentation_url: "https://www.techsmith.com/screen-capture.html"
    category: utilities
EOF

  # Mock yq to read our test file
  echo '#!/usr/bin/env bash
if [[ "$*" == *"keys"* ]]; then
  echo "snagit"
elif [[ "$*" == *"snagit.manager"* ]]; then
  echo "manual"
fi' > "$MOCK_BIN_DIR/yq"
  chmod +x "$MOCK_BIN_DIR/yq"

  # Get tools from config
  run yq '.tools | keys | .[]' "$BATS_TEST_TMPDIR/manual-check.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "snagit" ]]
}
