#!/usr/bin/env bats

load helpers/mocks.bash

setup() {
  setup_mocks

  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export BOOTSTRAP_SCRIPT="$REPO_ROOT/bootstrap.sh"
  export TEST_HOME
  TEST_HOME="$(mktemp -d)"
}

teardown() {
  teardown_mocks
  rm -rf "$TEST_HOME"
}

@test "bootstrap: help output includes examples" {
  run "$BOOTSTRAP_SCRIPT" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Examples:"* ]]
  [[ "$output" == *"--no-input"* ]]
}

@test "bootstrap: dry-run works non-interactively" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="darwin22" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-1password --skip-brewfile --skip-stow --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running in dry-run mode"* ]]
  [[ "$output" == *"[dry-run] Would execute: mkdir -p"* ]]
  [[ "$output" == *"Skipping 1Password installation"* ]]
  [[ "$output" != *"Do you use 1Password"* ]]
}

@test "bootstrap: explicit 1Password install is previewed in dry-run mode" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="darwin22" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --install-1password --skip-brewfile --skip-stow --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"brew install --cask 1password"* ]]
  [[ "$output" == *"brew install --cask 1password-cli"* ]]
}

@test "bootstrap: conflicting 1Password flags fail fast" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="darwin22" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --install-1password --skip-1password

  [ "$status" -eq 1 ]
  [[ "$output" == *"--install-1password and --skip-1password cannot be used together"* ]]
}
