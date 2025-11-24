#!/usr/bin/env bats

# Tests for Makefile functionality

setup() {
  # Save current directory
  export ORIGINAL_DIR="$PWD"
  export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_DIR="$(mktemp -d)"

  # Create a minimal test environment
  cd "$TEST_DIR"

  # Create mock install.sh that just prints its arguments
  cat > install.sh << 'EOF'
#!/usr/bin/env bash
echo "CONFIG_FILES: $CONFIG_FILES"
echo "Arguments: $@"
EOF
  chmod +x install.sh

  mkdir -p _macos
  cat > _macos/macos.sh <<'EOF'
#!/usr/bin/env bash
echo "macos.sh called with: $@"
EOF
  chmod +x _macos/macos.sh
  touch _macos/personal.yaml _macos/work.yaml

  # Copy the Makefile
  cp "$REPO_ROOT/Makefile" .
}

teardown() {
  cd "$ORIGINAL_DIR"
  rm -rf "$TEST_DIR"
}

@test "make help displays usage information" {
  run make help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "n-dotfiles" ]]
  [[ "$output" =~ "Dotfile and Tool Management" ]]
  [[ "$output" =~ "Main Configurations" ]]
  [[ "$output" =~ "common" ]]
  [[ "$output" =~ "personal" ]]
  [[ "$output" =~ "work" ]]
  [[ "$output" =~ "Focus Configurations" ]]
  [[ "$output" =~ "Actions" ]]
  [[ "$output" =~ "Examples" ]]
}

@test "make install defaults to personal profile" {
  run make install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "focus/containers" ]]
  [[ ! "$output" =~ "-u" ]]
  [[ ! "$output" =~ "-s" ]]
}

@test "make personal without action triggers install" {
  run make personal
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "focus/kubernetes" ]]
}

@test "make install work uses work profile" {
  run make install work
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/work" ]]
  [[ ! "$output" =~ "host/personal" ]]
}

@test "make work install uses work profile" {
  run make work install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/work" ]]
}

@test "make work stow adds stow flag" {
  run make work stow
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/work" ]]
  [[ "$output" =~ "-s" ]]
}

@test "make personal update adds update flag" {
  run make personal update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "-u" ]]
}

@test "make update defaults to personal profile" {
  run make update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "-u" ]]
}

@test "PROFILE environment variable overrides selection" {
  PROFILE=work run make install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/work" ]]
}

@test "make configure work calls macos.sh with work yaml" {
  run make configure work
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Applying macOS settings from _macos/work.yaml" ]]
  [[ "$output" =~ "macos.sh called with: work.yaml" ]]
}

@test "make vscode runs with correct configs" {
  run make vscode install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/vscode" ]]
}

@test "make default target shows help" {
  run make
  [ "$status" -eq 0 ]
  [[ "$output" =~ "n-dotfiles" ]]
  [[ "$output" =~ "Dotfile and Tool Management" ]]
}

@test "make work-setup runs setup-work-mac.sh" {
  cat > setup-work-mac.sh <<'EOF'
#!/usr/bin/env bash
echo "Running work setup"
EOF
  chmod +x setup-work-mac.sh

  run make work-setup
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Running work setup" ]]
}

@test "VSCODE_CLI environment variable is passed through" {
  # Update mock install.sh to show VSCODE_CLI
  cat > install.sh << 'EOF'
#!/usr/bin/env bash
echo "CONFIG_FILES: $CONFIG_FILES"
echo "VSCODE_CLI: $VSCODE_CLI"
echo "Arguments: $@"
EOF
  chmod +x install.sh

  VSCODE_CLI=cursor run make vscode install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VSCODE_CLI: cursor" ]]
}

@test "make with invalid target fails" {
  run make invalid_target
  [ "$status" -ne 0 ]
}
