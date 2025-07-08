#!/usr/bin/env bats

# Tests for Makefile functionality

setup() {
  # Save current directory
  export ORIGINAL_DIR="$PWD"
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
  
  # Copy the Makefile
  cp "$ORIGINAL_DIR/../Makefile" .
}

teardown() {
  cd "$ORIGINAL_DIR"
  rm -rf "$TEST_DIR"
}

@test "make help displays usage information" {
  run make help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "n-dotfiles Makefile wrapper for install.sh" ]]
  [[ "$output" =~ "Usage: make" ]]
  [[ "$output" =~ "Main targets:" ]]
  [[ "$output" =~ "common" ]]
  [[ "$output" =~ "personal" ]]
  [[ "$output" =~ "work" ]]
  [[ "$output" =~ "Focus targets" ]]
  [[ "$output" =~ "Actions" ]]
  [[ "$output" =~ "Examples:" ]]
}

@test "make common runs with correct configs" {
  run make common
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common" ]]
  [[ ! "$output" =~ "-u" ]]  # Should not have update flag
  [[ ! "$output" =~ "-s" ]]  # Should not have stow flag
}

@test "make personal runs with correct configs" {
  run make personal
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common host/personal focus/vscode" ]]
  [[ ! "$output" =~ "-u" ]]  # Should not have update flag
  [[ ! "$output" =~ "-s" ]]  # Should not have stow flag
}

@test "make work runs with correct configs" {
  run make work
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common host/work focus/vscode" ]]
  [[ ! "$output" =~ "host/personal" ]]  # Should not include personal configs
}

@test "make focus-vscode runs with correct configs" {
  run make focus-vscode
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/vscode" ]]
}

@test "make focus-devops runs with correct configs" {
  run make focus-devops
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/devops" ]]
}

@test "make focus-neovim runs with correct configs" {
  run make focus-neovim
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/neovim" ]]
}

@test "make common update adds update flag" {
  run make common update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common" ]]
  [[ "$output" =~ "-u" ]]  # Should have update flag
}

@test "make common stow adds stow flag" {
  run make common stow
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common" ]]
  [[ "$output" =~ "-s" ]]  # Should have stow flag
}

@test "make personal update adds update flag" {
  run make personal update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "-u" ]]  # Should have update flag
}

@test "make personal stow adds stow flag" {
  run make personal stow
  [ "$status" -eq 0 ]
  [[ "$output" =~ "-s" ]]  # Should have stow flag
}

@test "make personal install does not add extra flags" {
  run make personal install
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "-u" ]]  # Should not have update flag
  [[ ! "$output" =~ "-s" ]]  # Should not have stow flag
}

@test "make focus-vscode update adds update flag" {
  run make focus-vscode update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "-u" ]]
}

@test "make focus-vscode stow adds stow flag" {
  run make focus-vscode stow
  [ "$status" -eq 0 ]
  [[ "$output" =~ "-s" ]]
}

@test "make personal update stow adds both flags" {
  run make personal update stow
  [ "$status" -eq 0 ]
  [[ "$output" =~ "-u -s" ]]  # Should have both flags
}

@test "make common install stow adds stow flag" {
  run make common install stow
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common" ]]
  [[ "$output" =~ "-s" ]]  # Should have stow flag
  [[ ! "$output" =~ "-u" ]]  # Should not have update flag
}

@test "make default target shows help" {
  run make
  [ "$status" -eq 0 ]
  [[ "$output" =~ "n-dotfiles Makefile wrapper for install.sh" ]]
}

@test "make install alone does nothing" {
  run make install
  [ "$status" -eq 0 ]
  [ -z "$output" ]  # Should have no output
}

@test "make update alone does nothing" {
  run make update
  [ "$status" -eq 0 ]
  [ -z "$output" ]  # Should have no output
}

@test "make stow alone does nothing" {
  run make stow
  [ "$status" -eq 0 ]
  [ -z "$output" ]  # Should have no output
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
  
  VSCODE_CLI=cursor run make focus-vscode
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VSCODE_CLI: cursor" ]]
}

@test "make with invalid target fails" {
  run make invalid_target
  [ "$status" -ne 0 ]
}