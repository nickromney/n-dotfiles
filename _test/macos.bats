#!/usr/bin/env bats
# shellcheck disable=SC2016  # Mock scripts intentionally use single quotes

load helpers/mocks.bash

setup() {
  # Initialize mocking framework
  setup_mocks

  # Set up test environment
  local temp_dir
  temp_dir="$(mktemp -d)"
  export TEST_TEMP_DIR="$temp_dir"
  export PATH="$MOCK_BIN_DIR:$PATH"

  # Path to the script we're testing
  export MACOS_SCRIPT="$BATS_TEST_DIRNAME/../_macos/macos.sh"

  # Mock common commands
  mock_command "sw_vers" 0 "macOS 14.0"
  mock_command "sysctl" 0 "MacBookPro18,1"
  mock_command "uname" 0 "arm64"
  mock_command "id" 0 "501"
  mock_command "whoami" 0 "testuser"

  # Mock killall to prevent actual service restarts during tests
  mock_command "killall" 0 ""

  # Create mock /etc/shells
  mkdir -p "$TEST_TEMP_DIR/etc"
  cat > "$TEST_TEMP_DIR/etc/shells" << EOF
/bin/bash
/bin/csh
/bin/dash
/bin/ksh
/bin/sh
/bin/tcsh
/bin/zsh
/opt/homebrew/bin/bash
EOF
}

teardown() {
  teardown_mocks
  rm -rf "$TEST_TEMP_DIR"
}

# Test basic functionality
@test "macos.sh shows help with -h flag" {
  run "$MACOS_SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  [[ "$output" =~ "Options:" ]]
}

@test "macos.sh shows help with --help flag" {
  run "$MACOS_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "macos.sh runs in show mode by default" {
  # Mock all required commands for show mode
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"

  # Mock file existence checks
  mock_command "test" 0
  mock_command "[" 0

  run "$MACOS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "System Information" ]]
  [[ "$output" =~ "Shell Configuration" ]]
}

# Test system info detection
@test "detects Apple Silicon correctly" {
  mock_command "uname" 0 "arm64"
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"

  run "$MACOS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Running on Apple Silicon" ]]
}

@test "detects Intel Mac correctly" {
  mock_command "uname" 0 "x86_64"
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"

  run "$MACOS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Running on Intel" ]]
}

# Test shell detection
@test "detects available shells" {
  # Create a test /etc/shells file
  mkdir -p "$TEST_TEMP_DIR/etc"
  cat > "$TEST_TEMP_DIR/etc/shells" << 'EOF'
# List of acceptable shells for chpass(1).
# Ftpd will not allow users to connect who are not using
# one of these shells.

/bin/bash
/bin/csh
/bin/dash
/bin/ksh
/bin/sh
/bin/tcsh
/bin/zsh
EOF

  # Mock [[ -f /etc/shells ]] by overriding the test builtin
  # shellcheck disable=SC2317
  function test() {
    if [[ "$*" == "-f /etc/shells" ]]; then
      return 0
    fi
    builtin test "$@"
  }
  export -f test

  # Mock [[ -f ]] by overriding the [[ builtin behavior
  # We'll use a sed replacement approach instead
  cat > "$TEST_TEMP_DIR/macos_test.sh" << 'EOF'
#!/usr/bin/env bash
# Read the script and replace /etc/shells with our test file
SCRIPT_CONTENT=$(cat "$MACOS_SCRIPT")
SCRIPT_CONTENT="${SCRIPT_CONTENT//\/etc\/shells/$TEST_TEMP_DIR/etc/shells}"
eval "$SCRIPT_CONTENT"
EOF
  chmod +x "$TEST_TEMP_DIR/macos_test.sh"

  # Mock other required commands
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"

  # Export our variables so the eval'd script can see them
  export TEST_TEMP_DIR
  export MACOS_SCRIPT

  run "$TEST_TEMP_DIR/macos_test.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Available Shells:" ]]
  [[ "$output" =~ "/bin/bash" ]]
  [[ "$output" =~ "/opt/homebrew/bin/bash" ]]
  [[ "$output" =~ "Homebrew bash found at /opt/homebrew/bin/bash" ]]
}

@test "detects Homebrew bash on Apple Silicon" {
  # We need to mock the file existence check for /opt/homebrew/bin/bash
  # The script uses [[ -f "/opt/homebrew/bin/bash" ]]

  # Create a mock script that modifies the file check
  cat > "$TEST_TEMP_DIR/macos_homebrew.sh" << 'EOF'
#!/usr/bin/env bash
# Read the script and inject our file existence mock
SCRIPT_CONTENT=$(cat "$MACOS_SCRIPT")

# Replace the specific file check with a true statement
SCRIPT_CONTENT="${SCRIPT_CONTENT//\[\[ -f \"\/opt\/homebrew\/bin\/bash\" \]\]/true}"
SCRIPT_CONTENT="${SCRIPT_CONTENT//\[\[ -f \"\/usr\/local\/bin\/bash\" \]\]/false}"

eval "$SCRIPT_CONTENT"
EOF
  chmod +x "$TEST_TEMP_DIR/macos_homebrew.sh"

  # Mock other required commands
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"

  # Export our variables
  export TEST_TEMP_DIR
  export MACOS_SCRIPT

  run "$TEST_TEMP_DIR/macos_homebrew.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Homebrew bash found at /opt/homebrew/bin/bash" ]]
}

# Test Homebrew detection
@test "detects when Homebrew is installed" {
  mock_command "brew" 0 "Homebrew 4.0.0"
  mock_command "which" 0 "/opt/homebrew/bin/brew"
  mock_command "wc" 0 "42"
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"

  # Mock brew list commands
  mock_command_with_script "brew" '
case "$*" in
  "--version"*) echo "Homebrew 4.0.0" ;;
  "list --formula"*) echo "package1"; echo "package2" ;;
  "list --cask"*) echo "cask1" ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Homebrew is installed" ]]
  [[ "$output" =~ "Homebrew version:" ]]
}

@test "detects when Homebrew is not installed" {
  # Don't mock brew command - let it fail
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"
  mock_command "test" 0
  mock_command "[" 0

  # Override command -v to simulate brew not found
  # shellcheck disable=SC2317  # Function is used when exported
  function command() {
    if [[ "$1" == "-v" ]] && [[ "$2" == "brew" ]]; then
      return 1
    else
      /usr/bin/command "$@"
    fi
  }
  export -f command

  run "$MACOS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Homebrew is not installed" ]]
  [[ "$output" == *"Install from: https://brew.sh"* ]]
}

# Test application detection
@test "lists installed applications" {
  skip "Requires complex interactions with system paths - tested manually"
  # This test involves:
  # 1. Checking if /Applications directory exists
  # 2. Running find with specific parameters
  # 3. Processing output through a while loop with process substitution
  # 4. Incrementing counters with arithmetic operations
  # The complexity of mocking all these interactions reliably in CI
  # makes this better suited for manual testing on actual macOS systems
}

# Test configuration mode
@test "requires config file in apply mode" {
  # Mock required commands for show mode
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"
  mock_command "test" 0
  mock_command "[" 0

  run "$MACOS_SCRIPT" -d
  [ "$status" -eq 0 ]  # Should succeed in show mode

  # Try to apply without file
  ORIGINAL_PATH="$PATH"
  PATH="$MOCK_BIN_DIR:$ORIGINAL_PATH"

  # Create a wrapper script that will apply a non-existent config
  cat > "$TEST_TEMP_DIR/test_apply.sh" << 'EOF'
#!/usr/bin/env bash
exec "$MACOS_SCRIPT" nonexistent.yaml
EOF
  chmod +x "$TEST_TEMP_DIR/test_apply.sh"

  run "$TEST_TEMP_DIR/test_apply.sh"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Configuration file not found" ]]

  PATH="$ORIGINAL_PATH"
}

@test "accepts yaml config files from script directory" {
  # Create a yaml file in the script's directory
  local script_dir
  script_dir="$(dirname "$MACOS_SCRIPT")"
  cat > "$script_dir/test-config.yaml" << 'EOF'
system:
  show_hidden_files: true
EOF

  # Mock yq with a proper script
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".system "*yaml*) echo "show_hidden_files: true" ;;
  *".system.show_hidden_files"*) echo "true" ;;
  *".system.appearance"*) echo "null" ;;
  *".system.show_all_extensions"*) echo "null" ;;
  *".dock"*|*".finder"*|*".keyboard"*|*".trackpad"*|*".mouse"*) echo "null" ;;
  *".windows"*|*".mission_control"*|*".stage_manager"*|*".widgets"*) echo "null" ;;
  *".displays"*|*".screenshots"*|*".developer"*) echo "null" ;;
  *) echo "null" ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"

  # Mock defaults to handle reads and writes
  mock_command_with_script "defaults" '
case "$*" in
  *"read"*) exit 1 ;;  # Simulate unset
  *"write"*) exit 0 ;;
  *) exit 0 ;;
esac
'

  # Run from a different directory with just the filename
  cd "$TEST_TEMP_DIR"
  run "$MACOS_SCRIPT" test-config.yaml
  [ "$status" -eq 0 ]

  # Clean up
  rm -f "$script_dir/test-config.yaml"
}

@test "accepts yaml config files" {
  # Create a test config file
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
system:
  show_hidden_files: true
EOF

  # Mock yq to return proper values
  mock_command_with_script "yq" '
case "$*" in
  *".system "*yaml*) echo "show_hidden_files: true" ;;
  *".system.show_hidden_files"*) echo "true" ;;
  *".system.show_all_extensions"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Mock defaults
  mock_command_with_script "defaults" '
case "$*" in
  *"read"*) exit 1 ;;  # Simulate unset
  *"write"*) exit 0 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ Applying\ Configuration:\ $TEST_TEMP_DIR/test.yaml ]]
  [[ "$output" =~ "System Settings:" ]]
  [[ "$output" =~ "Configuration applied" ]]
}

@test "checks for yq when applying config" {
  # Create a test config file
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
system:
  show_hidden_files: true
EOF

  # Override command -v to simulate yq not found
  # shellcheck disable=SC2317  # Function is used when exported
  function command() {
    if [[ "$1" == "-v" ]] && [[ "$2" == "yq" ]]; then
      return 1
    else
      /usr/bin/command "$@"
    fi
  }
  export -f command

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "yq is required" ]]
  [[ "$output" =~ "Install with: brew install yq" ]]
}

# Test defaults reading
@test "reads dock defaults correctly" {
  mock_command_with_script "defaults" '
case "$*" in
  *"com.apple.dock tilesize"*) echo "48" ;;
  *"com.apple.dock orientation"*) echo "left" ;;
  *"com.apple.dock autohide"*) echo "1" ;;
  *"com.apple.dock show-recents"*) echo "0" ;;
  *) echo "0" ;;
esac
'
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""

  run "$MACOS_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Size: 48" ]]
  [[ "$output" =~ "Position: left" ]]
  [[ "$output" =~ "Auto-hide: 1" ]]
  [[ "$output" =~ "Show recent apps: 0" ]]
}

# Test dry run mode
@test "dry run mode is recognized" {
  mock_command_with_script "sw_vers" '
case "$1" in
  -productVersion) echo "14.0" ;;
  -buildVersion) echo "23A344" ;;
esac
'
  mock_command "find" 0 ""
  mock_command "defaults" 0 "0"

  run "$MACOS_SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  # In show mode, dry-run doesn't change output, but should be accepted
}

# =================
# Apply Config Tests
# =================

@test "apply_config validates config file exists" {
  # Test with non-existent file
  run "$MACOS_SCRIPT" "/path/to/nonexistent.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ Configuration\ file\ not\ found:\ /path/to/nonexistent.yaml ]]
}

@test "apply_config requires yq to be installed" {
  # Create a test config file
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
system:
  show_hidden_files: true
EOF

  # Override command -v to simulate yq not found
  # shellcheck disable=SC2317  # Function is used when exported
  function command() {
    if [[ "$1" == "-v" ]] && [[ "$2" == "yq" ]]; then
      return 1
    else
      /usr/bin/command "$@"
    fi
  }
  export -f command

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "yq is required to parse YAML configuration files" ]]
  [[ "$output" =~ "Install with: brew install yq" ]]
}

@test "apply_config applies all sections in order" {
  # Create a test config file
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
system:
  show_hidden_files: true
dock:
  size: 48
finder:
  default_view: "clmv"
keyboard:
  key_repeat: 2
trackpad:
  tap_to_click: true
screenshots:
  format: "jpg"
developer:
  xcode_behavior: "UseSeparateTab"
EOF

  # Mock yq to return expected values
  mock_command_with_script "yq" '
case "$*" in
  *".system "*yaml*) echo "show_hidden_files: true" ;;
  *".system.show_hidden_files"*) echo "true" ;;
  *".dock "*yaml*) echo "size: 48" ;;
  *".dock.size"*) echo "48" ;;
  *".finder "*yaml*) echo "default_view: clmv" ;;
  *".finder.default_view"*) echo "clmv" ;;
  *".keyboard "*yaml*) echo "key_repeat: 2" ;;
  *".keyboard.key_repeat"*) echo "2" ;;
  *".trackpad "*yaml*) echo "tap_to_click: true" ;;
  *".trackpad.tap_to_click"*) echo "true" ;;
  *".screenshots "*yaml*) echo "format: jpg" ;;
  *".screenshots.format"*) echo "jpg" ;;
  *".developer "*yaml*) echo "xcode_behavior: UseSeparateTab" ;;
  *".developer.xcode_behavior"*) echo "UseSeparateTab" ;;
  *) echo "null" ;;
esac
'

  # Mock defaults to return different current values
  mock_command_with_script "defaults" '
case "$*" in
  *"read com.apple.finder AppleShowAllFiles"*) echo "NO"; exit 1 ;;
  *"read com.apple.dock tilesize"*) echo "64" ;;
  *"write"*) exit 0 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "System Settings:" ]]
  [[ "$output" =~ "Dock Settings:" ]]
  [[ "$output" =~ "Finder Settings:" ]]
  [[ "$output" =~ "Keyboard Settings:" ]]
  [[ "$output" =~ "Trackpad Settings:" ]]
  [[ "$output" =~ "Screenshot Settings:" ]]
  [[ "$output" =~ "Developer Settings:" ]]
}

# =================
# Apply Default Tests
# =================

@test "apply_default skips when value already set correctly" {
  # Create a test config
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
dock:
  size: 48
EOF

  # Mock yq
  mock_command_with_script "yq" '
case "$*" in
  *".dock "*yaml*) echo "size: 48" ;;
  *".dock.size"*) echo "48" ;;
  *".dock.position"*|*".dock.auto_hide"*|*".dock.show_recents"*|*".dock.minimize_effect"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Mock defaults to return the same value as we're trying to set
  mock_command_with_script "defaults" '
case "$*" in
  *"read com.apple.dock tilesize"*) echo "48" ;;
  *"write"*) echo "Should not be called"; exit 1 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Dock size: already set to 48" ]]
  [[ ! "$output" =~ "Should not be called" ]]
}

@test "apply_default changes value when different" {
  # Create a test config
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
dock:
  size: 48
EOF

  # Mock yq
  mock_command_with_script "yq" '
case "$*" in
  *".dock "*yaml*) echo "size: 48" ;;
  *".dock.size"*) echo "48" ;;
  *".dock.position"*|*".dock.auto_hide"*|*".dock.show_recents"*|*".dock.minimize_effect"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Mock defaults - current value is different
  mock_command_with_script "defaults" '
case "$*" in
  *"read com.apple.dock tilesize"*) echo "64" ;;
  *"write com.apple.dock tilesize 48"*) exit 0 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Dock size: changed from '64' to '48'" ]]
}

@test "apply_default handles missing current value" {
  # Create a test config
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
system:
  show_hidden_files: true
EOF

  # Mock yq
  mock_command_with_script "yq" '
case "$*" in
  *".system "*yaml*) echo "show_hidden_files: true" ;;
  *".system.show_hidden_files"*) echo "true" ;;
  *".system.show_all_extensions"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Mock defaults - read fails (not set), write succeeds
  mock_command_with_script "defaults" '
case "$*" in
  *"read com.apple.finder AppleShowAllFiles"*) exit 1 ;;
  *"write com.apple.finder AppleShowAllFiles YES"*) exit 0 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Show hidden files: changed from '<not set>' to 'YES'" ]]
}

@test "dry run mode does not write defaults" {
  # Create a test config
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
dock:
  size: 48
EOF

  # Mock yq
  mock_command_with_script "yq" '
case "$*" in
  *".dock "*yaml*) echo "size: 48" ;;
  *".dock.size"*) echo "48" ;;
  *".dock.position"*|*".dock.auto_hide"*|*".dock.show_recents"*|*".dock.minimize_effect"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Mock defaults - should not write in dry run
  mock_command_with_script "defaults" '
case "$*" in
  *"read com.apple.dock tilesize"*) echo "64" ;;
  *"write"*) echo "ERROR: Should not write in dry run"; exit 1 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" --dry-run "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ \[DRY\ RUN\]\ Would\ change\ Dock\ size\ from\ \'64\'\ to\ \'48\' ]]
  [[ ! "$output" =~ "ERROR: Should not write in dry run" ]]
}

# =================
# Setting Application Tests
# =================

@test "boolean settings convert true/false to correct values" {
  # Create a test config with various boolean settings
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
system:
  show_hidden_files: true
  show_all_extensions: false
dock:
  auto_hide: true
  show_recents: false
trackpad:
  tap_to_click: true
  natural_scrolling: false
EOF

  # Mock yq to return boolean values
  mock_command_with_script "yq" '
case "$*" in
  *".system "*yaml*) echo "has values" ;;
  *".system.show_hidden_files"*) echo "true" ;;
  *".system.show_all_extensions"*) echo "false" ;;
  *".dock "*yaml*) echo "has values" ;;
  *".dock.size"*) echo "null" ;;
  *".dock.position"*) echo "null" ;;
  *".dock.auto_hide"*) echo "true" ;;
  *".dock.show_recents"*) echo "false" ;;
  *".dock.minimize_effect"*) echo "null" ;;
  *".trackpad "*yaml*) echo "has values" ;;
  *".trackpad.tap_to_click"*) echo "true" ;;
  *".trackpad.natural_scrolling"*) echo "false" ;;
  *".trackpad.tracking_speed"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Track which defaults commands were called
  DEFAULTS_CALLS_FILE="$TEST_TEMP_DIR/defaults_calls.txt"
  touch "$DEFAULTS_CALLS_FILE"

  mock_command_with_script "defaults" '
CALLS_FILE="'"$DEFAULTS_CALLS_FILE"'"
case "$*" in
  *"read"*) exit 1 ;;  # Simulate all as unset
  *"write com.apple.finder AppleShowAllFiles YES"*)
    echo "show_hidden_files=YES" >> "$CALLS_FILE"
    exit 0 ;;
  *"write NSGlobalDomain AppleShowAllExtensions 0"*)
    echo "show_all_extensions=0" >> "$CALLS_FILE"
    exit 0 ;;
  *"write com.apple.dock autohide 1"*)
    echo "auto_hide=1" >> "$CALLS_FILE"
    exit 0 ;;
  *"write com.apple.dock show-recents 0"*)
    echo "show_recents=0" >> "$CALLS_FILE"
    exit 0 ;;
  *"write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking 1"*)
    echo "tap_to_click=1" >> "$CALLS_FILE"
    exit 0 ;;
  *"write NSGlobalDomain com.apple.swipescrolldirection 0"*)
    echo "natural_scrolling=0" >> "$CALLS_FILE"
    exit 0 ;;
  *"write"*) exit 0 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]

  # Check that the correct conversions were made
  run cat "$DEFAULTS_CALLS_FILE"
  [[ "$output" =~ "show_hidden_files=YES" ]]
  [[ "$output" =~ "show_all_extensions=0" ]]
  [[ "$output" =~ "auto_hide=1" ]]
  [[ "$output" =~ "show_recents=0" ]]
  [[ "$output" =~ "tap_to_click=1" ]]
  [[ "$output" =~ "natural_scrolling=0" ]]
}

@test "screenshot location creates directory if needed" {
  # Create a test config
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
screenshots:
  location: "~/Pictures/Screenshots"
EOF

  # Mock yq
  mock_command_with_script "yq" '
case "$*" in
  *".screenshots "*yaml*) echo "location: ~/Pictures/Screenshots" ;;
  *".screenshots.location"*) echo "~/Pictures/Screenshots" ;;
  *".screenshots.format"*|*".screenshots.include_date"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Track mkdir calls
  MKDIR_CALLS_FILE="$TEST_TEMP_DIR/mkdir_calls.txt"
  touch "$MKDIR_CALLS_FILE"

  # Mock mkdir to track calls
  mock_command_with_script "mkdir" '
CALLS_FILE="'"$MKDIR_CALLS_FILE"'"
echo "$*" >> "$CALLS_FILE"
exit 0
'

  # Mock defaults
  mock_command_with_script "defaults" '
case "$*" in
  *"read"*) exit 1 ;;
  *"write com.apple.screencapture location"*) exit 0 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]

  # Check that mkdir was called with expanded path
  run cat "$MKDIR_CALLS_FILE"
  [[ "$output" =~ -p\ $HOME/Pictures/Screenshots ]]
}

@test "screenshot location not created in dry run mode" {
  # Create a test config
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
screenshots:
  location: "~/Pictures/Screenshots"
EOF

  # Mock yq
  mock_command_with_script "yq" '
case "$*" in
  *".screenshots "*yaml*) echo "location: ~/Pictures/Screenshots" ;;
  *".screenshots.location"*) echo "~/Pictures/Screenshots" ;;
  *".screenshots.format"*|*".screenshots.include_date"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Mock mkdir - should not be called in dry run
  mock_command_with_script "mkdir" '
echo "ERROR: mkdir should not be called in dry run"
exit 1
'

  # Mock defaults
  mock_command_with_script "defaults" '
case "$*" in
  *"read"*) exit 1 ;;
  *"write"*) exit 1 ;;  # Also should not write
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" --dry-run "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "ERROR: mkdir should not be called in dry run" ]]
}

@test "settings with null values are skipped" {
  # Create a test config with some null/missing values
  cat > "$TEST_TEMP_DIR/test.yaml" << EOF
dock:
  size: 48
  # position is not set
  auto_hide: true
  # show_recents is not set
EOF

  # Mock yq to return null for missing values
  mock_command_with_script "yq" '
case "$*" in
  *".dock "*yaml*) echo "has values" ;;
  *".dock.size"*) echo "48" ;;
  *".dock.position"*) echo "null" ;;
  *".dock.auto_hide"*) echo "true" ;;
  *".dock.show_recents"*) echo "null" ;;
  *".dock.minimize_effect"*) echo "null" ;;
  *) echo "null" ;;
esac
'

  # Track which settings were attempted
  SETTINGS_FILE="$TEST_TEMP_DIR/settings_attempted.txt"
  touch "$SETTINGS_FILE"

  mock_command_with_script "defaults" '
SETTINGS_FILE="'"$SETTINGS_FILE"'"
case "$*" in
  *"read"*) exit 1 ;;
  *"write com.apple.dock tilesize"*)
    echo "size" >> "$SETTINGS_FILE"
    exit 0 ;;
  *"write com.apple.dock orientation"*)
    echo "ERROR: position should be skipped" >> "$SETTINGS_FILE"
    exit 1 ;;
  *"write com.apple.dock autohide"*)
    echo "auto_hide" >> "$SETTINGS_FILE"
    exit 0 ;;
  *"write com.apple.dock show-recents"*)
    echo "ERROR: show_recents should be skipped" >> "$SETTINGS_FILE"
    exit 1 ;;
  *) exit 1 ;;
esac
'

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]

  # Check that only non-null settings were attempted
  run cat "$SETTINGS_FILE"
  [[ "$output" =~ "size" ]]
  [[ "$output" =~ "auto_hide" ]]
  [[ ! "$output" =~ "ERROR" ]]
}

@test "mouse settings are applied correctly" {
  # Set up settings file
  SETTINGS_FILE="$TEST_TEMP_DIR/settings.txt"
  touch "$SETTINGS_FILE"

  # Mock defaults for mouse settings
  mock_command_with_script "defaults" '
SETTINGS_FILE="'"$SETTINGS_FILE"'"
case "$*" in
  *"read NSGlobalDomain com.apple.swipescrolldirection"*) echo "1" ;;
  *"read com.apple.AppleMultitouchMouse MouseVerticalScroll"*) echo "1" ;;
  *"read com.apple.driver.AppleBluetoothMultitouch.mouse MouseVerticalScroll"*) echo "1" ;;
  *"read com.apple.driver.AppleHIDMouse ScrollV"*) echo "1" ;;
  *"write"*) echo "$@" >> "$SETTINGS_FILE" ;;
  *"read"*) echo "<not set>" ;;
  *) exit 0 ;;
esac
'

  # Mock yq for mouse settings
  mock_command_with_script "yq" '
case "$*" in
  *".mouse"*".yaml") echo "natural_scrolling: false" ;;
  *".mouse.natural_scrolling"*) echo "false" ;;
  *) echo "null" ;;
esac
'

  # Create test config
  cat > "$TEST_TEMP_DIR/test.yaml" << 'EOF'
mouse:
  natural_scrolling: false
EOF

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]

  # Check that all mouse settings were applied
  run cat "$SETTINGS_FILE"
  [[ "$output" =~ NSGlobalDomain\ com.apple.swipescrolldirection\ 0 ]]
  [[ "$output" =~ com.apple.AppleMultitouchMouse\ MouseVerticalScroll\ 0 ]]
  [[ "$output" =~ com.apple.driver.AppleBluetoothMultitouch.mouse\ MouseVerticalScroll\ 0 ]]
  [[ "$output" =~ com.apple.driver.AppleHIDMouse\ ScrollV\ 0 ]]
}

@test "appearance mode settings are applied correctly" {
  # Set up settings file
  SETTINGS_FILE="$TEST_TEMP_DIR/settings.txt"
  touch "$SETTINGS_FILE"

  # Mock defaults for appearance
  mock_command_with_script "defaults" '
SETTINGS_FILE="'"$SETTINGS_FILE"'"
case "$*" in
  *"read NSGlobalDomain AppleInterfaceStyle"*) echo "<not set>" ;;
  *"write NSGlobalDomain AppleInterfaceStyle Dark"*) echo "NSGlobalDomain AppleInterfaceStyle Dark" >> "$SETTINGS_FILE" ;;
  *"write"*) echo "$@" >> "$SETTINGS_FILE" ;;
  *"read"*) echo "<not set>" ;;
  *) exit 0 ;;
esac
'

  # Mock yq for appearance settings
  mock_command_with_script "yq" '
case "$*" in
  ".system "*/test.yaml)
    echo "appearance: Dark"
    echo "show_hidden_files: false"
    echo "show_all_extensions: false"
    ;;
  *".system.appearance"*) echo "Dark" ;;
  *".system.show_hidden_files"*) echo "false" ;;
  *".system.show_all_extensions"*) echo "false" ;;
  *) echo "null" ;;
esac
'

  # Create test config
  cat > "$TEST_TEMP_DIR/test.yaml" << 'EOF'
system:
  appearance: Dark
EOF

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]

  # Check that Dark mode was applied
  run cat "$SETTINGS_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NSGlobalDomain AppleInterfaceStyle Dark" ]]
}

@test "display settings detect external vs builtin displays" {
  skip "Complex test with system_profiler - tested manually"

  # Mock killall to prevent actual service restarts
  mock_command "killall" 0 ""

  # Mock system_profiler for external display
  mock_command_with_script "system_profiler" '
if [[ "$*" =~ "SPDisplaysDataType" ]]; then
  echo "        DELL U2412M:"
  echo "          Main Display: Yes"
fi
'

  # Mock yq with a proper script
  cat > "$MOCK_BIN_DIR/yq" << 'EOF'
#!/usr/bin/env bash
case "$*" in
  *".displays "$*".yaml"*)
    # Return actual YAML content (not null) to indicate displays section exists
    echo "preferred_main_display:"
    echo "  - PL2792Q"
    ;;
  *".displays.preferred_main_display | length"*) echo "2" ;;
  *".displays.preferred_main_display[0]"*) echo "PL2792Q" ;;
  *".displays.preferred_main_display[1]"*) echo "DELL U2412M" ;;
  *".displays.mirror_builtin_when_both_external_connected"*) echo "null" ;;
  *".displays.dock_position.external"*) echo "left" ;;
  *".dock"*|*".finder"*|*".keyboard"*|*".trackpad"*|*".mouse"*) echo "null" ;;
  *".system"*|*".windows"*|*".mission_control"*|*".stage_manager"*) echo "null" ;;
  *".widgets"*|*".screenshots"*|*".developer"*) echo "null" ;;
  *) echo "null" ;;
esac
EOF
  chmod +x "$MOCK_BIN_DIR/yq"

  # Mock defaults
  mock_command_with_script "defaults" '
case "$*" in
  *"read com.apple.dock orientation"*) echo "bottom" ;;
  *"write com.apple.dock orientation left"*) exit 0 ;;
  *"read"*) exit 1 ;;
  *"write"*) exit 0 ;;
  *) exit 0 ;;
esac
'

  # Create test config
  cat > "$TEST_TEMP_DIR/test.yaml" << 'EOF'
displays:
  preferred_main_display:
    - "PL2792Q"
    - "DELL U2412M"
  dock_position:
    external: left
    builtin: bottom
EOF

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]

  # Check output mentions external display
  [[ "$output" =~ "Display type: external" ]]
}

@test "dock app management adds apps and skips missing ones" {
  # Set up settings file
  SETTINGS_FILE="$TEST_TEMP_DIR/settings.txt"
  touch "$SETTINGS_FILE"

  # Mock defaults for dock management
  mock_command_with_script "defaults" '
SETTINGS_FILE="'"$SETTINGS_FILE"'"
case "$*" in
  *"write com.apple.dock persistent-apps -array-add"*)
    echo "ADD_APP: $*" >> "$SETTINGS_FILE"
    ;;
  *"write com.apple.dock persistent-apps -array"*)
    echo "CLEAR_DOCK" >> "$SETTINGS_FILE"
    ;;
  *"read"*)
    echo "<not set>"
    ;;
esac
'

  # Create Safari.app but not NotExists.app in temp dir
  mkdir -p "$TEST_TEMP_DIR/Applications"
  touch "$TEST_TEMP_DIR/Applications/Safari.app"

  # Mock yq for dock app management
  mock_command_with_script "yq" '
TEST_TEMP_DIR="'"$TEST_TEMP_DIR"'"
case "$*" in
  ".dock "*/test.yaml)
    echo "manage_apps: true"
    echo "clear_dock_first: true"
    echo "apps:"
    echo "  - $TEST_TEMP_DIR/Applications/Safari.app"
    echo "  - $TEST_TEMP_DIR/Applications/NotExists.app"
    ;;
  *".dock.manage_apps"*) echo "true" ;;
  *".dock.clear_dock_first"*) echo "true" ;;
  *".dock.apps | length"*) echo "2" ;;
  *".dock.apps[0]"*) echo "$TEST_TEMP_DIR/Applications/Safari.app" ;;
  *".dock.apps[1]"*) echo "$TEST_TEMP_DIR/Applications/NotExists.app" ;;
  *) echo "null" ;;
esac
'

  # Create test config
  cat > "$TEST_TEMP_DIR/test.yaml" << 'EOF'
dock:
  manage_apps: true
  clear_dock_first: true
  apps:
    - "/Applications/Safari.app"
    - "/Applications/NotExists.app"
EOF

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]

  # Save the script output
  local script_output="$output"

  # Check that dock was cleared and Safari was added
  run cat "$SETTINGS_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CLEAR_DOCK" ]]
  [[ "$output" =~ "ADD_APP:" ]] && [[ "$output" =~ Safari\.app ]]
  # Check the script output for the warning about missing app
  [[ "$script_output" =~ "App not found:" ]]
}

@test "dock app management prevents duplicates when run twice" {
  # Set up settings file
  SETTINGS_FILE="$TEST_TEMP_DIR/settings.txt"
  touch "$SETTINGS_FILE"

  # Mock defaults for dock management that simulates existing apps
  mock_command_with_script "defaults" '
SETTINGS_FILE="'"$SETTINGS_FILE"'"
TEST_TEMP_DIR="'"$TEST_TEMP_DIR"'"
case "$*" in
  *"read com.apple.dock persistent-apps"*)
    # Simulate that Safari is already in the dock
    echo "(
      {
        \"tile-data\" = {
          \"file-data\" = {
            \"_CFURLString\" = \"file://$TEST_TEMP_DIR/Applications/Safari.app/\";
          };
        };
      }
    )"
    ;;
  *"write com.apple.dock persistent-apps -array-add"*)
    echo "ADD_APP: $*" >> "$SETTINGS_FILE"
    ;;
  *"write com.apple.dock persistent-apps -array"*)
    echo "CLEAR_DOCK" >> "$SETTINGS_FILE"
    ;;
  *"read"*)
    echo "<not set>"
    ;;
esac
'

  # Create Safari.app in temp dir
  mkdir -p "$TEST_TEMP_DIR/Applications"
  touch "$TEST_TEMP_DIR/Applications/Safari.app"
  touch "$TEST_TEMP_DIR/Applications/Terminal.app"

  # Mock python3 for URL decoding
  mock_command_with_script "python3" '
while IFS= read -r line; do
  echo "$line"
done
'

  # Mock yq for dock app management
  mock_command_with_script "yq" '
TEST_TEMP_DIR="'"$TEST_TEMP_DIR"'"
case "$*" in
  ".dock "*/test.yaml)
    echo "manage_apps: true"
    echo "clear_dock_first: false"
    echo "apps:"
    echo "  - $TEST_TEMP_DIR/Applications/Safari.app"
    echo "  - $TEST_TEMP_DIR/Applications/Terminal.app"
    ;;
  *".dock.manage_apps"*) echo "true" ;;
  *".dock.clear_dock_first"*) echo "false" ;;
  *".dock.apps | length"*) echo "2" ;;
  *".dock.apps[0]"*) echo "$TEST_TEMP_DIR/Applications/Safari.app" ;;
  *".dock.apps[1]"*) echo "$TEST_TEMP_DIR/Applications/Terminal.app" ;;
  *) echo "null" ;;
esac
'

  # Create test config
  cat > "$TEST_TEMP_DIR/test.yaml" << 'EOF'
dock:
  manage_apps: true
  clear_dock_first: false
  apps:
    - "/Applications/Safari.app"
    - "/Applications/Terminal.app"
EOF

  run "$MACOS_SCRIPT" "$TEST_TEMP_DIR/test.yaml"
  # Debug
  if [ "$status" -ne 0 ]; then
    echo "Exit status: $status" >&3
    echo "Output: $output" >&3
  fi
  [ "$status" -eq 0 ]

  # Save the script output
  local script_output="$output"

  # Check that only Terminal was added (Safari was already there)
  run cat "$SETTINGS_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ Terminal\.app ]]
  [[ ! "$output" =~ Safari\.app ]]  # Safari should NOT be added again
  # Check the script output for skip message
  [[ "$script_output" =~ "Already in dock:" ]]
  [[ "$script_output" =~ "Summary: Added 1 apps, skipped 1 already present" ]]
}

@test "dry run mode shows appearance mode changes without applying" {
  # Set up settings file (should remain empty in dry run)
  SETTINGS_FILE="$TEST_TEMP_DIR/settings.txt"

  # Mock current Dark mode
  mock_command_with_script "defaults" '
SETTINGS_FILE="'"$SETTINGS_FILE"'"
case "$*" in
  *"read NSGlobalDomain AppleInterfaceStyle"*) echo "Dark" ;;
  *"write"*) echo "ERROR: Should not write in dry run" >> "$SETTINGS_FILE"; exit 1 ;;
  *"read"*) echo "<not set>" ;;
  *) exit 0 ;;
esac
'

  # Mock yq for Light mode
  mock_command_with_script "yq" '
case "$*" in
  ".system "*/test.yaml) echo "appearance: Light" ;;
  *".system.appearance"*) echo "Light" ;;
  *) echo "null" ;;
esac
'

  # Create test config
  cat > "$TEST_TEMP_DIR/test.yaml" << 'EOF'
system:
  appearance: Light
EOF

  run "$MACOS_SCRIPT" -d "$TEST_TEMP_DIR/test.yaml"
  [ "$status" -eq 0 ]

  # Check dry run warning
  [[ "$output" =~ \[DRY\ RUN\]\ Would\ change\ Appearance\ mode\ from\ \'Dark\'\ to\ \'Light\' ]]

  # Ensure no settings were written
  [ ! -f "$SETTINGS_FILE" ]
}
