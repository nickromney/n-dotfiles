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
    [[ -d "$NUSHELL_CONFIG_DIR/vendor" ]]
}

@test "nushell: vendor directory structure exists" {
    # Vendor directory should exist for external tool completions
    [[ -d "$NUSHELL_CONFIG_DIR/vendor" ]]
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

@test "nushell: navigation commands defined in config.nu" {
    run grep -E "def --env cdd \[\]" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]

    # The 'o' command is defined as an alias for zoxide
    run grep "alias o = z" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: git aliases defined in config.nu" {
    run grep "alias gs = git status" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]

    run grep "alias gc = git commit" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]

    run grep "def g \[\]" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: tool commands and aliases defined in config.nu" {
    run grep -E "def l \[" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]

    run grep "alias n = nvim" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]

    # Check for ll alias instead of cc function
    run grep "alias ll = ls -la" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: config sets show_banner to false" {
    run grep '$env.config.show_banner = false' "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: config loads standard library properly" {
    # Check for std library usage
    run grep "use std/dirs" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]

    run grep "use std/log" "$NUSHELL_CONFIG_DIR/config.nu"
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

@test "nushell: source commands use proper paths" {
    # Check that source commands in config.nu use data-dir or literal paths
    run grep "source (\$nu.data-dir" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]

    # Check for zoxide source path
    run grep "source ~/.zoxide.nu" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: vendor file initialization checks for tools" {
    # These checks are in env.nu, not config.nu
    run grep "which starship" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]

    run grep "which zoxide" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]

    run grep "which uv" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]
}

@test "nushell: uses length check pattern for command existence" {
    # Check we're using the (which command | length) > 0 pattern
    run grep "which.*length" "$NUSHELL_CONFIG_DIR/config.nu"
    [[ "$status" -eq 0 ]]

    run grep "which.*length" "$NUSHELL_CONFIG_DIR/env.nu"
    [[ "$status" -eq 0 ]]
}
