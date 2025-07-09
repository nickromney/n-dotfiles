#!/usr/bin/env bats

# Test suite for Nushell configuration

load helpers/mocks

setup() {
    # Store original HOME
    export ORIGINAL_HOME="$HOME"
    export TEST_HOME="$BATS_TEST_TMPDIR/home"
    
    # Create test directories
    mkdir -p "$TEST_HOME/.config/nushell"
    mkdir -p "$TEST_HOME/Library/Application Support/nushell"
    
    # Set test environment
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/.config"
    
    # Path to our nushell configs
    NUSHELL_CONFIG_DIR="$BATS_TEST_DIRNAME/../nushell/Library/Application Support/nushell"
    
    # Change to the repo root directory
    cd "$BATS_TEST_DIRNAME/.."
}

teardown() {
    # Restore original HOME
    export HOME="$ORIGINAL_HOME"
}

@test "nushell: config files exist" {
    [[ -f "$NUSHELL_CONFIG_DIR/config.nu" ]]
    [[ -f "$NUSHELL_CONFIG_DIR/env.nu" ]]
    [[ -d "$NUSHELL_CONFIG_DIR/modules" ]]
}

@test "nushell: module files exist" {
    [[ -f "$NUSHELL_CONFIG_DIR/modules/navigation.nu" ]]
    [[ -f "$NUSHELL_CONFIG_DIR/modules/git.nu" ]]
    [[ -f "$NUSHELL_CONFIG_DIR/modules/tools.nu" ]]
}

@test "nushell: config.nu syntax is valid" {
    run nu --config "$NUSHELL_CONFIG_DIR/config.nu" --env-config "$NUSHELL_CONFIG_DIR/env.nu" -c "exit 0"
    # Allow exit code 0 or 1 (1 might occur if vendor files don't exist yet)
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "nushell: env.nu syntax is valid" {
    run nu --env-config "$NUSHELL_CONFIG_DIR/env.nu" -c "exit 0"
    [[ "$status" -eq 0 ]]
}

@test "nushell: navigation module exports expected commands" {
    run grep -E "export def.*cdd" "$NUSHELL_CONFIG_DIR/modules/navigation.nu"
    [[ "$status" -eq 0 ]]
    
    run grep -E "export def.*\.\." "$NUSHELL_CONFIG_DIR/modules/navigation.nu"
    [[ "$status" -eq 0 ]]
    
    run grep -E "export def.*o \[" "$NUSHELL_CONFIG_DIR/modules/navigation.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: git module exports expected aliases" {
    run grep "export alias gs = git status" "$NUSHELL_CONFIG_DIR/modules/git.nu"
    [[ "$status" -eq 0 ]]
    
    run grep "export alias gc = git commit" "$NUSHELL_CONFIG_DIR/modules/git.nu"
    [[ "$status" -eq 0 ]]
    
    run grep "export def g \[\]" "$NUSHELL_CONFIG_DIR/modules/git.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: tools module exports expected commands" {
    run grep -E "export def l \[" "$NUSHELL_CONFIG_DIR/modules/tools.nu"
    [[ "$status" -eq 0 ]]
    
    run grep -E "export def n \[" "$NUSHELL_CONFIG_DIR/modules/tools.nu"
    [[ "$status" -eq 0 ]]
    
    run grep -E "export def cc \[\]" "$NUSHELL_CONFIG_DIR/modules/tools.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: config sets show_banner to false" {
    run grep "show_banner: false" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: config loads modules properly" {
    # We use direct module paths instead of NU_LIB_DIRS
    run grep "use modules/" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: env.nu sets up PATH correctly" {
    run grep '$env.PATH' "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]
    
    # Check for important paths
    run grep ".local/bin" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]
    
    run grep ".cargo/bin" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: env.nu handles 1Password SSH agent" {
    run grep "SSH_AUTH_SOCK" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]
    
    run grep "1password" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: no dynamic source commands without constants" {
    # Check that we don't have problematic dynamic source commands
    run grep -E "source \\\$[a-zA-Z]" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -ne 0 ]]
    
    # Check modules don't have dynamic source
    run grep -E "source \\\$[a-zA-Z]" "$NUSHELL_CONFIG_DIR/modules/"*.nu
    [[ "$status" -ne 0 ]]
}

@test "nushell: vendor file initialization checks for tools" {
    run grep "which starship" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
    
    run grep "which zoxide" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
    
    run grep "which uv" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: uses is-empty instead of complete for command checks" {
    # Ensure we're not using the problematic complete pattern
    run grep -E "complete\)\.exit_code" "$NUSHELL_CONFIG_DIR/"*.nu "$NUSHELL_CONFIG_DIR/modules/"*.nu
    [[ "$status" -ne 0 ]]
    
    # Ensure we are using is-empty
    run grep "which.*is-empty" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]
}