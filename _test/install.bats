#!/usr/bin/env bats

load helpers/mocks

# Setup and teardown
setup() {
  setup_mocks
  
  # Set up test environment - use the real tools.yaml
  export YAML_FILE="$BATS_TEST_DIRNAME/../tools.yaml"
  export DRY_RUN="false"
  export VERBOSE="false"
  export STOW="false"
  export FORCE="false"
  
  # Change to the script directory to ensure relative paths work
  cd "$BATS_TEST_DIRNAME/.."
  
  # Save the original type builtin
  # Note: We can't actually save builtins, but we can override them
  
  # Source the install script functions only (not main)
  set +e  # Temporarily disable errexit
  source ./install.sh --source-only
  set -e  # Re-enable errexit
}

teardown() {
  teardown_mocks
}

# Tests for command_exists function
@test "command_exists returns success for existing command" {
  mock_command "test-cmd"
  
  run command_exists "test-cmd"
  [ "$status" -eq 0 ]
}

@test "command_exists returns failure for non-existing command" {
  run command_exists "non-existent-cmd"
  [ "$status" -eq 1 ]
}

# Tests for check_requirements function
@test "check_requirements succeeds when all required commands exist" {
  mock_command "yq"
  mock_command "which"
  
  run check_requirements
  [ "$status" -eq 0 ]
}

@test "check_requirements fails when yq is missing" {
  # Override command_exists to simulate yq missing
  command_exists() {
    [[ "$1" == "which" ]] && return 0
    return 1
  }
  export -f command_exists
  
  run check_requirements
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing required commands: yq" ]]
}

@test "check_requirements fails when which is missing" {
  # Override command_exists to simulate which missing
  command_exists() {
    [[ "$1" == "yq" ]] && return 0
    return 1
  }
  export -f command_exists
  
  run check_requirements
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing required commands: which" ]]
}

@test "check_requirements fails when both commands are missing" {
  # Override command_exists to simulate both missing
  command_exists() {
    return 1
  }
  export -f command_exists
  
  run check_requirements
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing required commands: yq which" ]]
}

# Tests for get_available_managers function
@test "get_available_managers detects brew when available" {
  # Mock yq to return brew as a manager
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    echo "brew"
    ;;
  *)
    echo "null"
    ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"
  
  run get_available_managers
  [ "$status" -eq 0 ]
  
  # Check if brew is actually available on the system
  if command_exists brew; then
    [[ "$output" =~ "Available package managers: brew" ]]
  else
    [[ "$output" =~ "brew: please install from https://brew.sh" ]]
  fi
}

@test "get_available_managers detects multiple managers" {
  # Mock yq to return common managers
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    echo "brew"
    echo "cargo"
    echo "uv"
    ;;
  *)
    echo "null"
    ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"
  
  run get_available_managers
  [ "$status" -eq 0 ]
  
  # Should show some managers as available based on what's actually installed
  [[ "$output" =~ "Available package managers:" ]] || [[ "$output" =~ "Unavailable package managers:" ]]
}

@test "get_available_managers reports unavailable managers" {
  # Mock yq to return managers that might not be installed
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    # List some managers that are likely not installed everywhere
    echo "apt"      # Not on macOS
    echo "arkade"   # Often not installed
    echo "fakemgr"  # Doesn't exist
    ;;
  *)
    echo "null"
    ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"
  
  run get_available_managers
  [ "$status" -eq 0 ]
  
  # Should report at least one unavailable manager
  [[ "$output" =~ "Unavailable package managers:" ]]
  
  # Check for specific messages based on platform
  if [[ "$(uname)" == "Darwin" ]]; then
    # On macOS, apt should be unavailable
    [[ "$output" =~ "apt: apt-get is not available on this system" ]]
  fi
  
  # fakemgr should always be reported as unknown
  [[ "$output" =~ "unknown package manager: fakemgr" ]]
}

@test "get_available_managers handles unknown package manager" {
  # Create a custom mock that includes a fake 'foo' manager
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    echo "brew"
    echo "foo"
    echo "arkade"
    ;;
  *".tools.\"*\".manager"*)
    echo "foo"
    ;;
  *)
    echo "null"
    ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"
  
  # Mock brew as available
  mock_command "brew"
  
  run get_available_managers
  [ "$status" -eq 0 ]
  # Check that brew is listed as available (might be with other managers)
  [[ "$output" =~ "Available package managers:" ]] && [[ "$output" =~ "brew" ]]
  [[ "$output" =~ "unknown package manager: foo" ]]
}

@test "get_available_managers handles apt on non-root user" {
  # Skip this test on non-Linux systems
  if [[ "$(uname)" != "Linux" ]]; then
    skip "apt test only relevant on Linux"
  fi
  
  # Mock yq to include apt as a manager
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    echo "apt"
    ;;
  *)
    echo "null"
    ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"
  
  # Mock id to return non-root
  mock_id 1000
  
  run get_available_managers
  [ "$status" -eq 0 ]
  
  # On Linux with apt-get available but not root, should show permission message
  if command_exists apt-get; then
    [[ "$output" =~ "apt: requires root privileges - please run with sudo" ]]
  else
    [[ "$output" =~ "apt: apt-get is not available on this system" ]]
  fi
}

@test "get_available_managers handles apt on root user" {
  mock_yq
  mock_command "apt-get"
  mock_id 0
  
  run get_available_managers
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ "Available package managers:" ]] && [[ "${lines[0]}" =~ "apt" ]]
}

# Tests for is_tool_installed function
@test "is_tool_installed returns success when tool is installed" {
  mock_yq
  mock_command "tool1" 0
  
  run is_tool_installed "tool1"
  [ "$status" -eq 0 ]
}

@test "is_tool_installed returns failure when tool is not installed" {
  mock_yq
  
  run is_tool_installed "tool2"
  [ "$status" -eq 1 ]
}

@test "is_tool_installed handles tools with no check command" {
  mock_yq
  
  run is_tool_installed "special-tool"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "no check command specified" ]]
}

# Tests for can_install_tool function
@test "can_install_tool returns success when manager is available" {
  mock_yq
  AVAILABLE_MANAGERS=("brew" "arkade")
  
  run can_install_tool "tool1"
  [ "$status" -eq 0 ]
}

@test "can_install_tool returns failure when manager is not available" {
  mock_yq
  AVAILABLE_MANAGERS=("arkade")
  
  run can_install_tool "tool1"
  [ "$status" -eq 1 ]
}

# Tests for install_tool function - Brew
@test "install_tool installs brew package" {
  mock_yq
  mock_brew
  
  run install_tool "jq"
  [ "$status" -eq 0 ]
  assert_mock_called "brew" "install jq"
}

@test "install_tool installs brew cask" {
  mock_yq
  mock_brew
  
  run install_tool "docker"
  [ "$status" -eq 0 ]
  assert_mock_called "brew" "install --cask docker"
}

@test "install_tool installs brew tap" {
  mock_yq
  mock_brew
  
  run install_tool "homebrew/cask-fonts"
  [ "$status" -eq 0 ]
  assert_mock_called "brew" "tap homebrew/cask-fonts"
}

# Tests for install_tool function - Arkade
@test "install_tool installs arkade get tool" {
  mock_yq
  mock_arkade
  
  run install_tool "kubectl"
  [ "$status" -eq 0 ]
  assert_mock_called "arkade" "get kubectl"
}

@test "install_tool installs arkade system tool" {
  mock_yq
  mock_arkade
  
  run install_tool "prometheus"
  [ "$status" -eq 0 ]
  assert_mock_called "arkade" "system install prometheus"
}

@test "install_tool installs arkade app" {
  mock_yq
  mock_arkade
  
  run install_tool "openfaas"
  [ "$status" -eq 0 ]
  assert_mock_called "arkade" "install openfaas --namespace openfaas"
}

# Tests for install_tool function - Cargo
@test "install_tool installs cargo binary" {
  mock_yq
  mock_cargo
  
  run install_tool "ripgrep"
  [ "$status" -eq 0 ]
  assert_mock_called "cargo" "install ripgrep"
}

@test "install_tool installs cargo git package" {
  mock_yq
  mock_cargo
  
  run install_tool "zoxide"
  [ "$status" -eq 0 ]
  assert_mock_called "cargo" "install --git https://github.com/ajeetdsouza/zoxide zoxide"
}

# Tests for install_tool function - UV
@test "install_tool installs uv tool" {
  mock_yq
  mock_uv
  
  run install_tool "ruff"
  [ "$status" -eq 0 ]
  assert_mock_called "uv" "tool install ruff"
}

# Tests for install_tool function - APT
@test "install_tool installs apt package" {
  mock_yq
  mock_apt_get
  
  run install_tool "curl"
  [ "$status" -eq 0 ]
  assert_mock_called "apt-get" "update -qq"
  assert_mock_called "apt-get" "install -y curl"
}

# Tests for install_tool with dry run
@test "install_tool respects dry run mode" {
  mock_yq
  mock_brew
  export DRY_RUN="true"
  
  run install_tool "jq"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Would execute: brew install" ]] && [[ "$output" =~ "jq" ]]
  assert_mock_not_called "brew"
}

# Tests for run_stow function
@test "run_stow fails when stow is not installed" {
  # Override command_exists to simulate stow not installed
  command_exists() {
    return 1
  }
  export -f command_exists
  
  run run_stow
  [ "$status" -eq 1 ]
  [[ "$output" =~ "stow is not installed" ]]
}

@test "run_stow processes directories correctly" {
  mock_stow
  
  # Create test directories
  mkdir -p "$BATS_TEST_DIRNAME/../zsh"
  mkdir -p "$BATS_TEST_DIRNAME/../git"
  
  run run_stow
  [ "$status" -eq 0 ]
  assert_mock_called "stow"
}

@test "run_stow respects dry run mode" {
  mock_stow
  export DRY_RUN="true"
  
  mkdir -p "$BATS_TEST_DIRNAME/../zsh"
  
  run run_stow
  [ "$status" -eq 0 ]
  assert_mock_called "stow" "--no"
}

@test "run_stow respects force mode" {
  mock_stow
  export FORCE="true"
  
  mkdir -p "$BATS_TEST_DIRNAME/../zsh"
  
  run run_stow
  [ "$status" -eq 0 ]
  assert_mock_called "stow" "--adopt"
}

# Tests for is_root function
@test "is_root returns true when uid is 0" {
  mock_id 0
  
  run is_root
  [ "$status" -eq 0 ]
}

@test "is_root returns false when uid is not 0" {
  mock_id 1000
  
  run is_root
  [ "$status" -eq 1 ]
}

# Integration tests
@test "main function with no available managers" {
  # Create a simple mock that returns managers that don't exist
  mock_command_with_script "yq" '
case "$*" in
  ".tools[].manager"*)
    echo "fakemgr1"
    echo "fakemgr2"
    exit 0
    ;;
  ".tools | keys | .[]"*)
    # Return empty list of tools
    exit 0
    ;;
  *)
    echo "null"
    exit 0
    ;;
esac
'
  mock_command "which"
  
  # Override command_exists to simulate no managers available
  command_exists() {
    [[ "$1" == "yq" ]] && return 0
    [[ "$1" == "which" ]] && return 0
    return 1
  }
  export -f command_exists
  
  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *"No package managers available"* ]]
}

@test "main function installs tools with available managers" {
  # Create custom yq mock that only returns tool1
  mock_command_with_script "yq" '
case "$*" in
  ".tools[].manager"*)
    echo "brew"
    exit 0
    ;;
  ".tools | keys | .[]"*)
    echo "tool1"
    exit 0
    ;;
  ".tools.tool1.manager"*)
    echo "brew"
    exit 0
    ;;
  ".tools.tool1.type"*)
    echo "package"
    exit 0
    ;;
  ".tools.tool1.check_command"*)
    echo "tool1 --version"
    exit 0
    ;;
  ".tools.tool1.install_args[]"*)
    exit 0
    ;;
  *)
    echo "null"
    exit 0
    ;;
esac
'
  mock_command "which"
  mock_brew
  
  # tool1 is not installed (not in our mock bin)
  
  run main
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Installing tool1" ]]
  assert_mock_called "brew"
}

@test "main function skips already installed tools" {
  # Create custom yq mock that only returns tool1
  mock_command_with_script "yq" '
case "$*" in
  ".tools[].manager"*)
    echo "brew"
    exit 0
    ;;
  ".tools | keys | .[]"*)
    echo "tool1"
    exit 0
    ;;
  ".tools.tool1.manager"*)
    echo "brew"
    exit 0
    ;;
  ".tools.tool1.type"*)
    echo "package"
    exit 0
    ;;
  ".tools.tool1.check_command"*)
    echo "tool1 --version"
    exit 0
    ;;
  ".tools.tool1.install_args[]"*)
    exit 0
    ;;
  *)
    echo "null"
    exit 0
    ;;
esac
'
  mock_command "which"
  mock_brew
  
  # Mock tool1 as installed
  mock_command "tool1" 0
  
  run main
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tool1 is already installed" ]]
  assert_mock_not_called "brew"
}

@test "main function runs stow when requested" {
  # Simple mock that returns brew as available manager
  mock_command_with_script "yq" '
case "$*" in
  ".tools[].manager"*)
    echo "brew"
    exit 0
    ;;
  ".tools | keys | .[]"*)
    # Return empty - no tools to install
    exit 0
    ;;
  *)
    echo "null"
    exit 0
    ;;
esac
'
  mock_command "which"
  mock_brew
  mock_stow
  export STOW="true"
  
  mkdir -p "$BATS_TEST_DIRNAME/../zsh"
  
  run main
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Running stow" ]]
  assert_mock_called "stow"
}

@test "main function handles tools with unknown package managers" {
  # Create a custom mock that includes a tool with unknown manager
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".tools[].manager"*)
    echo "brew"
    echo "foo"
    ;;
  *".tools | keys | .[]"*)
    echo "tool1"
    echo "footool"
    ;;
  *".tools.tool1.manager"*)
    echo "brew"
    ;;
  *".tools.footool.manager"*)
    echo "foo"
    ;;
  *".tools.tool1.check_command"*)
    echo "which tool1"
    ;;
  *".tools.footool.check_command"*)
    echo "which footool >/dev/null 2>&1"
    ;;
  *)
    echo "package"
    ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"
  
  mock_command "brew"
  mock_command "tool1"  # Mark tool1 as already installed
  
  # Create a smart 'which' mock that checks if commands exist in mock dir
  cat > "$MOCK_BIN_DIR/which" << 'EOF'
#!/usr/bin/env bash
# Smart which mock that actually checks for existence
cmd="$1"
if [[ -x "$MOCK_BIN_DIR/$cmd" ]]; then
  echo "$MOCK_BIN_DIR/$cmd"
  exit 0
else
  exit 1
fi
EOF
  chmod +x "$MOCK_BIN_DIR/which"
  
  run main
  [ "$status" -eq 0 ]
  [[ "$output" =~ "unknown package manager: foo" ]]
  [[ "$output" =~ "Skipping footool: foo not available" ]]
}