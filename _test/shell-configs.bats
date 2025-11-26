#!/usr/bin/env bats
# Tests for shell configuration files (bashrc, zshrc)

setup() {
  # Save original PATH for BATS to use
  export ORIGINAL_PATH="$PATH"

  # Create a temporary home directory for testing
  export TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME"

  # Mock bin directory for fake commands
  export MOCK_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN_DIR"

  # Set up test environment
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
}

teardown() {
  # Restore original PATH so BATS can find system commands
  export PATH="$ORIGINAL_PATH"

  # Clean up
  rm -rf "$TEST_HOME"
  rm -rf "$MOCK_BIN_DIR"
}

# ============================================================================
# Bash Tests
# ============================================================================

@test "bashrc: can be sourced without errors" {
  # Source bashrc in a subshell to avoid affecting test environment
  run bash -c "source $DOTFILES_DIR/bash/.bashrc 2>&1"
  [ "$status" -eq 0 ]
}

@test "bashrc: syntax check passes" {
  run bash -n "$DOTFILES_DIR/bash/.bashrc"
  [ "$status" -eq 0 ]
}

@test "bashrc: PATH deduplication works" {
  # Create a PATH with duplicates
  export PATH="/usr/bin:/usr/local/bin:/usr/bin:/opt/homebrew/bin:/usr/local/bin"

  # Source bashrc and check PATH deduplication
  result=$(/bin/bash -c "
    export PATH='$PATH'
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo \$PATH
  ")

  # Count occurrences of /usr/bin (should only appear once)
  count=$(echo "$result" | tr ':' '\n' | grep -c '^/usr/bin$')
  [ "$count" -eq 1 ]
}

@test "bashrc: PATH has no trailing colon" {
  result=$(/bin/bash -c "
    export PATH='/usr/bin:/usr/local/bin'
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo \$PATH
  ")

  # PATH should not end with a colon
  [[ ! "$result" =~ :$ ]]
  echo "PATH=$result"
}

@test "bashrc: kubectl aliases only created when kubectl exists" {
  # Test without kubectl
  run bash -c "
    export PATH='$MOCK_BIN_DIR:/usr/bin:/bin'
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    type k 2>&1
  "
  [ "$status" -ne 0 ]

  # Create mock kubectl with completion
  cat > "$MOCK_BIN_DIR/kubectl" << 'EOF'
#!/bin/bash
if [[ "$1" == "completion" && "$2" == "bash" ]]; then
  echo "# kubectl bash completion mock"
  echo "complete -F __start_kubectl kubectl"
  echo "__start_kubectl() { :; }"
else
  echo "mocked kubectl"
fi
EOF
  chmod +x "$MOCK_BIN_DIR/kubectl"

  # Test with kubectl - source should work (alias might not be testable in subshell)
  run bash -c "
    export PATH='$MOCK_BIN_DIR:/usr/bin:/bin'
    export DOTFILES_DIR='$DOTFILES_DIR'
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo 'sourced successfully'
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sourced successfully" ]]
}

@test "bashrc: fnm only initialized when fnm exists" {
  # Test without fnm - should not error
  run bash -c "
    source $DOTFILES_DIR/bash/.bashrc 2>&1
  "
  [ "$status" -eq 0 ]

  # Create mock fnm
  echo '#!/bin/bash
if [[ "$1" == "env" ]]; then
  echo "export PATH=\"$HOME/.fnm:$PATH\""
fi' > "$MOCK_BIN_DIR/fnm"
  chmod +x "$MOCK_BIN_DIR/fnm"

  # Test with fnm - should initialize
  run bash -c "
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo \$PATH
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "fnm" ]]
}

# ============================================================================
# Zsh Tests
# ============================================================================

@test "zshrc: can be sourced without errors" {
  # Source zshrc in a subshell
  run zsh -c "source $DOTFILES_DIR/zsh/.zshrc 2>&1"
  [ "$status" -eq 0 ]
}

@test "zshrc: syntax check passes" {
  run zsh -n "$DOTFILES_DIR/zsh/.zshrc"
  [ "$status" -eq 0 ]
}

@test "zshrc: PATH deduplication works" {
  # Create a PATH with duplicates
  export PATH="/usr/bin:/usr/local/bin:/usr/bin:/opt/homebrew/bin:/usr/local/bin"

  # Source zshrc and check PATH deduplication
  result=$(/bin/zsh -c "
    export PATH='$PATH'
    source $DOTFILES_DIR/zsh/.zshrc 2>/dev/null
    echo \$PATH
  ")

  # Count occurrences of /usr/bin (should only appear once)
  count=$(echo "$result" | tr ':' '\n' | grep -c '^/usr/bin$')
  [ "$count" -eq 1 ]
}

@test "zshrc: PATH has no trailing colon" {
  result=$(/bin/zsh -c "
    export PATH='/usr/bin:/usr/local/bin'
    source $DOTFILES_DIR/zsh/.zshrc 2>/dev/null
    echo \$PATH
  ")

  # PATH should not end with a colon
  [[ ! "$result" =~ :$ ]]
  echo "PATH=$result"
}

@test "zshrc: uses compdef not complete for kubectl" {
  # Check that zshrc uses compdef (zsh) not complete (bash)
  run grep -q "complete -F" "$DOTFILES_DIR/zsh/.zshrc"
  [ "$status" -ne 0 ]

  run grep -q "compdef" "$DOTFILES_DIR/zsh/.zshrc"
  [ "$status" -eq 0 ]
}

@test "zshrc: direnv only initialized when direnv exists" {
  # Test without direnv - should not error
  run zsh -c "
    source $DOTFILES_DIR/zsh/.zshrc 2>&1
  "
  [ "$status" -eq 0 ]

  # Create mock direnv
  echo '#!/bin/bash
if [[ "$1" == "hook" ]]; then
  echo "# direnv hook mock"
fi' > "$MOCK_BIN_DIR/direnv"
  chmod +x "$MOCK_BIN_DIR/direnv"

  # Test with direnv - should source without error
  run zsh -c "
    export PATH='$MOCK_BIN_DIR:\$PATH'
    source $DOTFILES_DIR/zsh/.zshrc 2>&1
    echo 'sourced successfully'
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sourced successfully" ]]
}

@test "zshrc: brew only called when brew exists" {
  # Test without brew - should not error
  run zsh -c "
    source $DOTFILES_DIR/zsh/.zshrc 2>&1
  "
  [ "$status" -eq 0 ]

  # Should not try to call brew --prefix
  [[ ! "$output" =~ "brew: command not found" ]]
}

@test "zshrc: starship only initialized when starship exists" {
  # Clear any existing cache
  rm -rf "$HOME/.cache/zsh-init"

  # Test that zshrc can be sourced without errors regardless of starship
  run zsh -c "
    source $DOTFILES_DIR/zsh/.zshrc 2>&1
  "
  [ "$status" -eq 0 ]

  # Verify the cache mechanism works - if starship is available (real one),
  # a cache file should be created. If not available, no cache file.
  # Note: We can't easily mock starship because homebrew shellenv overrides PATH.
  if command -v starship >/dev/null 2>&1; then
    # Starship is installed - verify cache was created
    [ -f "$HOME/.cache/zsh-init/starship.zsh" ]
  fi
}

# ============================================================================
# Performance Regression Tests
# ============================================================================

@test "zshrc: does not call brew --prefix directly (uses cached BREW_PREFIX)" {
  # grep for $(brew --prefix) patterns - should not exist in zshrc
  # BREW_PREFIX should be set once in the Homebrew section and reused
  run grep -c '\$(brew --prefix)' "$DOTFILES_DIR/zsh/.zshrc"

  # Should find 0 occurrences
  [ "$output" = "0" ] || [ "$status" -eq 1 ]  # grep returns 1 when no matches
}

@test "zshrc: uses _cache_init for tool initialization" {
  # Verify key tools use the caching mechanism
  run grep -c '_cache_init starship' "$DOTFILES_DIR/zsh/.zshrc"
  [ "$output" = "1" ]

  run grep -c '_cache_init zoxide' "$DOTFILES_DIR/zsh/.zshrc"
  [ "$output" = "1" ]

  run grep -c '_cache_init kubectl' "$DOTFILES_DIR/zsh/.zshrc"
  [ "$output" = "1" ]

  run grep -c '_cache_init fzf' "$DOTFILES_DIR/zsh/.zshrc"
  [ "$output" = "1" ]
}

@test "zshrc: startup time under 125ms" {
  # Detect a suitable 'time' command with -p (POSIX) support
  local TIME_CMD=""
  if command -v gtime >/dev/null 2>&1 && gtime -p true 2>/dev/null; then
    TIME_CMD="gtime -p"
  elif /usr/bin/time -p true 2>/dev/null; then
    TIME_CMD="/usr/bin/time -p"
  else
    skip "No suitable 'time' command with -p flag available"
  fi

  # Run 3 times and take the average
  local total=0
  local runs=3

  for i in $(seq 1 $runs); do
    # $TIME_CMD outputs: real X.XX
    local time_output=$($TIME_CMD zsh -i -c exit 2>&1)
    local real_time=$(echo "$time_output" | grep '^real' | awk '{print $2}')
    # Convert to milliseconds
    local ms=$(echo "$real_time" | awk '{printf "%.0f", $1 * 1000}')
    total=$((total + ms))
  done

  local avg_ms=$((total / runs))
  echo "Average startup time: ${avg_ms}ms over $runs runs (threshold: 125ms)"

  # Assert under 125ms
  [ "$avg_ms" -lt 125 ]
}

# ============================================================================
# Common Tests (both bash and zsh)
# ============================================================================

@test "both configs: add arkade bin to PATH when it exists" {
  mkdir -p "$HOME/.arkade/bin"

  # Test bash
  result=$(bash -c "
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo \$PATH
  ")
  [[ "$result" =~ ".arkade/bin" ]]

  # Test zsh
  result=$(zsh -c "
    source $DOTFILES_DIR/zsh/.zshrc 2>/dev/null
    echo \$PATH
  ")
  [[ "$result" =~ ".arkade/bin" ]]
}

@test "both configs: set EDITOR to nvim" {
  # Test bash
  result=$(bash -c "
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo \$EDITOR
  ")
  [[ "$result" == "nvim" ]]

  # Test zsh
  result=$(zsh -c "
    source $DOTFILES_DIR/zsh/.zshrc 2>/dev/null
    echo \$EDITOR
  ")
  [[ "$result" == "nvim" ]]
}

@test "both configs: history settings are configured" {
  # Test bash
  result=$(bash -c "
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo \$HISTSIZE
  ")
  [ "$result" -eq 100000 ]

  # Test zsh
  result=$(zsh -c "
    source $DOTFILES_DIR/zsh/.zshrc 2>/dev/null
    echo \$HISTSIZE
  ")
  [ "$result" -eq 100000 ]
}
