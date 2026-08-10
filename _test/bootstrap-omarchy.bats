#!/usr/bin/env bats

load helpers/mocks.bash

setup() {
  setup_mocks

  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export BOOTSTRAP_SCRIPT="$REPO_ROOT/bootstrap-omarchy.sh"
  export TEST_HOME
  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME/.local/share/omarchy"

  mock_command "sudo" 0 ""
  mock_command "mise" 0 ""
  mock_command "hyprctl" 0 ""
  mock_stow
}

teardown() {
  teardown_mocks
  rm -rf "$TEST_HOME"
}

@test "bootstrap-omarchy: help output includes examples" {
  run "$BOOTSTRAP_SCRIPT" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Examples:"* ]]
  [[ "$output" == *"--no-input"* ]]
}

@test "bootstrap-omarchy: refuses to run without an Omarchy install directory" {
  local empty_home
  empty_home="$(mktemp -d)"

  run env \
    HOME="$empty_home" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input

  [ "$status" -eq 1 ]
  [[ "$output" == *"Omarchy install directory not found"* ]]

  rm -rf "$empty_home"
}

@test "bootstrap-omarchy: refuses to run on macOS" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="darwin22" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input

  [ "$status" -eq 1 ]
  [[ "$output" == *"Arch/Omarchy"* ]]
}

@test "bootstrap-omarchy: dry-run works non-interactively" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running in dry-run mode"* ]]
  [[ "$output" == *"[dry-run] Would execute: mkdir -p"* ]]
  [[ "$output" == *"--noconfirm"* ]]
}

@test "bootstrap-omarchy: skip flags are honoured" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input \
    --skip-pacman --skip-stow --skip-keyd --skip-hypr --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping pacman base packages"* ]]
  [[ "$output" == *"Skipping stow"* ]]
  [[ "$output" == *"Skipping keyd setup"* ]]
  [[ "$output" == *"Skipping Hyprland hyper.conf include"* ]]
  [[ "$output" == *"Skipping tools and runtimes via mise"* ]]
}

@test "bootstrap-omarchy: keyd setup is skipped when default.conf is not stowed" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-pacman --skip-stow --skip-hypr --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"stow the omarchy package first"* ]]
}

@test "bootstrap-omarchy: hyper.conf include is appended once" {
  mkdir -p "$TEST_HOME/.config/hypr"
  touch "$TEST_HOME/.config/hypr/bindings.conf"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"Added hyper.conf include"* ]]
  grep -qxF "source = ~/.config/hypr/hyper.conf" "$TEST_HOME/.config/hypr/bindings.conf"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"already included"* ]]
  [ "$(grep -cxF "source = ~/.config/hypr/hyper.conf" "$TEST_HOME/.config/hypr/bindings.conf")" -eq 1 ]
}

@test "bootstrap-omarchy: custom stow package list is passed through" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-pacman --skip-keyd --skip-hypr --skip-mise --packages "git zsh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Stowing dotfiles (git zsh)"* ]]
}

@test "bootstrap-omarchy: warns when a zsh plugin file is missing" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    ZSH_PLUGIN_DIR="$TEST_HOME/no-such-plugin-dir" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-pacman --skip-keyd --skip-hypr --skip-mise --packages "zsh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN zsh-autosuggestions: zsh is stowed, but"* ]]
  [[ "$output" == *"WARN zsh-syntax-highlighting: zsh is stowed, but"* ]]
}

@test "bootstrap-omarchy: passes when zsh plugin files are present" {
  local plugin_dir="$TEST_HOME/plugins"
  mkdir -p "$plugin_dir/zsh-autosuggestions" "$plugin_dir/zsh-syntax-highlighting"
  touch "$plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"
  touch "$plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    ZSH_PLUGIN_DIR="$plugin_dir" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-pacman --skip-keyd --skip-hypr --skip-mise --packages "zsh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"zsh-autosuggestions and zsh-syntax-highlighting are both present."* ]]
}

@test "bootstrap-omarchy: skips the zsh plugin check when zsh is not in the package list" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    ZSH_PLUGIN_DIR="$TEST_HOME/no-such-plugin-dir" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-pacman --skip-keyd --skip-hypr --skip-mise --packages "git"

  [ "$status" -eq 0 ]
  [[ "$output" != *"zsh-autosuggestions"* ]]
}

@test "bootstrap-omarchy: warns when a stowed package's tool is not installed" {
  mock_command "git" 0 ""

  # Even on hosts where zsh is genuinely installed system-wide, this must
  # still exclude it to exercise the "missing" branch.
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:$(path_excluding zsh)" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-pacman --skip-keyd --skip-hypr --skip-mise --packages "git zsh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN zsh: config stowed, but 'zsh' is not on PATH"* ]]
  [[ "$output" != *"WARN git:"* ]]
}

@test "bootstrap-omarchy: a failing mise install does not abort the rest of the script" {
  mock_command "mise" 1 ""

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-hypr

  [ "$status" -eq 0 ]
  [[ "$output" == *"mise install reported failures"* ]]
  [[ "$output" == *"Bootstrap complete!"* ]]
}
