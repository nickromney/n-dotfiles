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

  # zshrc/bashrc honour $XDG_CACHE_HOME when set, so without this override
  # a real value inherited from the outer shell (common in dev environments)
  # makes tested configs write cache files outside $TEST_HOME entirely —
  # both escaping test isolation and leaking into the real cache dir.
  export XDG_CACHE_HOME="$TEST_HOME/.cache"
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

@test "bashrc: mise only initialized when mise exists" {
  # Test without mise - should not error
  run bash -c "
    source $DOTFILES_DIR/bash/.bashrc 2>&1
  "
  [ "$status" -eq 0 ]

  # Create mock mise
  cat > "$MOCK_BIN_DIR/mise" << 'EOF'
#!/bin/bash
if [[ "$1" == "activate" && "$2" == "bash" ]]; then
  echo "export PATH=\"$HOME/.local/share/mise/bin:$PATH\""
fi
EOF
  chmod +x "$MOCK_BIN_DIR/mise"

  # Test with mise - should source successfully
  run bash -c "
    export PATH='$MOCK_BIN_DIR:\$PATH'
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo 'sourced successfully'
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sourced successfully" ]]
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

@test "zshrc: does not execute codex while starting a shell" {
  local marker="$TEST_HOME/codex-called"
  cat >"$MOCK_BIN_DIR/codex" <<EOF
#!/usr/bin/env bash
touch "$marker"
EOF
  chmod +x "$MOCK_BIN_DIR/codex"

  run env \
    HOME="$TEST_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    zsh -c "source $DOTFILES_DIR/zsh/.zshrc"

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "zoxide: cross-platform shell dependency is managed by mise only" {
  run grep -Eq '^zoxide = "[^"]+"' "$DOTFILES_DIR/mise/.config/mise/config.toml"
  [ "$status" -eq 0 ]

  run grep -Eq '^brew "zoxide"' "$DOTFILES_DIR/Brewfile"
  [ "$status" -ne 0 ]

  run grep -Eq '^brew "zoxide"' "$DOTFILES_DIR/Brewfile.posix"
  [ "$status" -ne 0 ]
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

@test "zshrc: prepends docker completions directory to fpath when present" {
  mkdir -p "$HOME/.docker/completions"
  touch "$HOME/.docker/completions/_docker"

  result=$(/bin/zsh -c "
    export HOME='$HOME'
    export DOTFILES_DIR='$DOTFILES_DIR'
    source $DOTFILES_DIR/zsh/.zshrc 2>/dev/null
    print -r -- \$fpath[1]
  ")

  [ "$result" = "$HOME/.docker/completions" ]
}

@test "zshrc: direnv only initialized when direnv exists" {
  # Test without direnv - should not error
  run zsh -c "
    source $DOTFILES_DIR/zsh/.zshrc 2>&1
  "
  [ "$status" -eq 0 ]

  # Create mock direnv
  cat > "$MOCK_BIN_DIR/direnv" << 'EOF'
#!/bin/bash
if [[ "$1" == "hook" ]]; then
  echo "# direnv hook mock"
fi
EOF
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
  run grep -F -c "\$(brew --prefix)" "$DOTFILES_DIR/zsh/.zshrc"

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

  # mise is deliberately NOT cached: mise activate's output bakes in a
  # literal PATH snapshot from generation time, so caching it would freeze
  # PATH to whatever it was on first run (see the dedicated regression test
  # "zshrc: does not cache mise activate output to a file").
  run grep -c '_cache_init mise' "$DOTFILES_DIR/zsh/.zshrc"
  [ "$output" = "0" ]
}

@test "zshrc: startup time under 125ms" {
  # Detect a suitable 'time' command with -p (POSIX) support
  local -a time_cmd=()
  if command -v gtime >/dev/null 2>&1 && gtime -p true 2>/dev/null; then
    time_cmd=(gtime -p)
  elif /usr/bin/time -p true 2>/dev/null; then
    time_cmd=(/usr/bin/time -p)
  else
    skip "No suitable 'time' command with -p flag available"
  fi

  local zdotdir="$HOME/zdotdir"
  mkdir -p "$zdotdir"
  ln -sf "$DOTFILES_DIR/zsh/.zshrc" "$zdotdir/.zshrc"
  if [ -f "$DOTFILES_DIR/zsh/.zshenv" ]; then
    ln -sf "$DOTFILES_DIR/zsh/.zshenv" "$zdotdir/.zshenv"
  fi

  local -a zsh_cmd=(
    env
    HOME="$HOME"
    DOTFILES_DIR="$DOTFILES_DIR"
    ZDOTDIR="$zdotdir"
    TERM="xterm-256color"
    zsh -i -c exit
  )

  # Warm caches first so we measure the steady-state startup path.
  run "${zsh_cmd[@]}"
  [ "$status" -eq 0 ]

  # Run 3 times and take the average
  local total=0
  local runs=3

  local run_idx
  for ((run_idx = 1; run_idx <= runs; run_idx++)); do
    # $TIME_CMD outputs: real X.XX
    local time_output
    time_output=$("${time_cmd[@]}" "${zsh_cmd[@]}" 2>&1 >/dev/null)
    local real_time
    real_time=$(echo "$time_output" | grep '^real' | awk '{print $2}')
    # Convert to milliseconds
    local ms
    ms=$(echo "$real_time" | awk '{printf "%.0f", $1 * 1000}')
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

@test "both configs: add mise shims to PATH before Homebrew path" {
  mkdir -p "$HOME/.local/share/mise/shims"

  # Test bash
  result=$(bash -c "
    export PATH='/opt/homebrew/bin:/usr/bin:/bin'
    source $DOTFILES_DIR/bash/.bashrc 2>/dev/null
    echo \$PATH
  ")
  [[ "$result" == *"mise/shims"* ]]
  bash_shims_index=$(echo "$result" | tr ':' '\n' | nl -ba | awk '$2 ~ /mise\/shims$/ {print $1; exit}')
  bash_brew_index=$(echo "$result" | tr ':' '\n' | nl -ba | awk '$2 == "/opt/homebrew/bin" {print $1; exit}')
  [ -n "$bash_shims_index" ]
  [ -n "$bash_brew_index" ]
  [ "$bash_shims_index" -lt "$bash_brew_index" ]

  # Test zsh
  result=$(zsh -c "
    export PATH='/opt/homebrew/bin:/usr/bin:/bin'
    source $DOTFILES_DIR/zsh/.zshrc 2>/dev/null
    echo \$PATH
  ")
  [[ "$result" == *"mise/shims"* ]]
  zsh_shims_index=$(echo "$result" | tr ':' '\n' | nl -ba | awk '$2 ~ /mise\/shims$/ {print $1; exit}')
  zsh_brew_index=$(echo "$result" | tr ':' '\n' | nl -ba | awk '$2 == "/opt/homebrew/bin" {print $1; exit}')
  [ -n "$zsh_shims_index" ]
  [ -n "$zsh_brew_index" ]
  [ "$zsh_shims_index" -lt "$zsh_brew_index" ]
}

@test "zshrc: does not cache mise activate output to a file" {
  # mise activate's output bakes in a literal `export PATH='...'` snapshot
  # of the PATH at generation time, so caching it (like starship/direnv/etc)
  # would freeze PATH to whatever it was on first run instead of
  # recomputing it fresh each shell.
  run zsh -c "source $DOTFILES_DIR/zsh/.zshrc 2>&1"
  [ "$status" -eq 0 ]
  [ ! -f "$XDG_CACHE_HOME/zsh-init/mise.zsh" ]
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
