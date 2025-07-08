#!/usr/bin/env bats

# Test for Makefile functionality

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
  [[ "$output" =~ "Usage: make" ]]
  [[ "$output" =~ "Profiles:" ]]
  [[ "$output" =~ "Actions:" ]]
  [[ "$output" =~ "Examples:" ]]
}

@test "make personal runs with correct configs" {
  run make personal
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: shared/shell shared/search shared/git shared/neovim shared/file-tools shared/data-tools shared/network host/common host/personal" ]]
  [[ ! "$output" =~ "-u" ]]  # Should not have update flag
  [[ ! "$output" =~ "-s" ]]  # Should not have stow flag
}

@test "make work runs with correct configs" {
  run make work
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: shared/shell shared/search shared/git shared/neovim shared/file-tools shared/data-tools shared/network host/common host/work" ]]
  [[ ! "$output" =~ "host/personal" ]]  # Should not include personal configs
}

@test "make python runs with correct configs" {
  run make python
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/container-base focus/python" ]]
}

@test "make typescript runs with correct configs" {
  run make typescript
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/container-base focus/typescript" ]]
}

@test "make rust runs with correct configs" {
  run make rust
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/container-base focus/rust" ]]
}

@test "make ai runs with correct configs" {
  run make ai
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/container-base focus/ai" ]]
}

@test "make kubernetes runs with correct configs" {
  run make kubernetes
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/container-base focus/kubernetes" ]]
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

@test "make all runs with all configs" {
  run make all
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES:" ]]
  [[ "$output" =~ "shared/shell" ]]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "focus/python" ]]
  [[ "$output" =~ "focus/typescript" ]]
  [[ "$output" =~ "focus/rust" ]]
  [[ "$output" =~ "focus/ai" ]]
  [[ "$output" =~ "focus/kubernetes" ]]
  [[ "$output" =~ "-s" ]]  # all target includes stow
}

@test "make with invalid target fails" {
  run make invalid_target
  [ "$status" -ne 0 ]
}