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
  # shellcheck disable=SC2016 # Expanded by the generated mock at runtime.
  mock_command_with_script "getent" 'echo "${2:-nick}:x:1000:1000::/home/test:/usr/bin/bash"'
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
  [[ "$output" == *"Stowing dotfiles (git zsh tmux mise codex claude agents omarchy)"* ]]
  [[ "$output" != *"Stowing dotfiles (git zsh nvim"* ]]
}

@test "bootstrap-omarchy: skip flags are honoured" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input \
    --skip-pacman --skip-stow --skip-shell --skip-keyd --skip-hypr --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping pacman base packages"* ]]
  [[ "$output" == *"Skipping stow"* ]]
  [[ "$output" == *"Skipping login shell setup"* ]]
  [[ "$output" == *"Skipping keyd setup"* ]]
  [[ "$output" == *"Skipping Hyprland hyper.conf include"* ]]
  [[ "$output" == *"Skipping tools and runtimes via mise"* ]]
}

@test "bootstrap-omarchy: sets zsh as the login shell through the public flow" {
  ln -s "$REPO_ROOT/zsh/.zshrc" "$TEST_HOME/.zshrc"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-hypr --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"Setting Zsh as the login shell"* ]]
  assert_mock_called sudo "chsh -s /usr/bin/zsh"
}

@test "bootstrap-omarchy: leaves an existing zsh login shell unchanged" {
  # shellcheck disable=SC2016 # Expanded by the generated mock at runtime.
  mock_command_with_script "getent" 'echo "${2:-nick}:x:1000:1000::/home/test:/usr/bin/zsh"'
  ln -s "$REPO_ROOT/zsh/.zshrc" "$TEST_HOME/.zshrc"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-hypr --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"already the login shell"* ]]
  assert_mock_not_called sudo
}

@test "bootstrap-omarchy: does not change shells when zsh is omitted from the Stow list" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-hypr --skip-mise --packages "git"

  [ "$status" -eq 0 ]
  [[ "$output" == *"zsh Stow package was not requested"* ]]
  assert_mock_not_called sudo
}

@test "bootstrap-omarchy: refuses to change shells when the personalized zshrc is not active" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-hypr --skip-mise --packages "zsh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"is not linked to this repository"* ]]
  assert_mock_not_called sudo
}

@test "bootstrap-omarchy: refuses a zsh binary absent from the valid shells list" {
  local shells_file="$TEST_HOME/shells"
  printf '%s\n' /usr/bin/bash >"$shells_file"
  ln -s "$REPO_ROOT/zsh/.zshrc" "$TEST_HOME/.zshrc"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    SHELLS_FILE="$shells_file" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-hypr --skip-mise --packages "zsh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"is not listed in $shells_file"* ]]
  assert_mock_not_called sudo
}

@test "bootstrap-omarchy: refuses to change shells when account lookup fails" {
  mock_command "getent" 2 ""
  ln -s "$REPO_ROOT/zsh/.zshrc" "$TEST_HOME/.zshrc"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-hypr --skip-mise --packages "zsh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"could not read the account record"* ]]
  assert_mock_not_called sudo
}

@test "bootstrap-omarchy: keyd setup is skipped when omarchy is not requested" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-pacman --skip-stow --skip-shell --skip-hypr --skip-mise --packages "git"

  [ "$status" -eq 0 ]
  [[ "$output" == *"stow the omarchy package first"* ]]
}

@test "bootstrap-omarchy: fresh-machine dry-run previews keyd for the omarchy package" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    KEYD_LINK="$TEST_HOME/n-dotfiles.conf" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --dry-run --no-input --skip-pacman --skip-stow --skip-shell --skip-hypr --skip-mise --packages "omarchy"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Setting up keyd"* ]]
  [[ "$output" == *"sudo ln -s $TEST_HOME/.config/keyd/default.conf"* ]]
}

@test "bootstrap-omarchy: refuses an unexpected existing keyd link" {
  local keyd_link="$TEST_HOME/n-dotfiles.conf"
  mkdir -p "$TEST_HOME/.config/keyd"
  touch "$TEST_HOME/.config/keyd/default.conf" "$TEST_HOME/unexpected.conf"
  ln -s "$TEST_HOME/unexpected.conf" "$keyd_link"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    KEYD_LINK="$keyd_link" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-shell --skip-hypr --skip-mise --packages "omarchy"

  [ "$status" -eq 0 ]
  [[ "$output" == *"does not point to"* ]]
  [[ "$output" == *"Refusing to replace"* ]]
  assert_mock_not_called sudo
}

@test "bootstrap-omarchy: hyper.conf include is appended once" {
  mkdir -p "$TEST_HOME/.config/hypr"
  touch "$TEST_HOME/.config/hypr/bindings.conf"
  touch "$TEST_HOME/.config/hypr/hyper.conf"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"Added hyper.conf include"* ]]
  grep -qxF "source = ~/.config/hypr/hyper.conf" "$TEST_HOME/.config/hypr/bindings.conf"
  assert_mock_called hyprctl "reload"
  assert_mock_called hyprctl "configerrors"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-keyd --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"already included"* ]]
  [ "$(grep -cxF "source = ~/.config/hypr/hyper.conf" "$TEST_HOME/.config/hypr/bindings.conf")" -eq 1 ]
}

@test "bootstrap-omarchy: does not include a missing hyper config when omarchy is omitted" {
  mkdir -p "$TEST_HOME/.config/hypr"
  touch "$TEST_HOME/.config/hypr/bindings.conf"

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-stow --skip-shell --skip-keyd --skip-mise --packages "git"

  [ "$status" -eq 0 ]
  [[ "$output" == *"stow the omarchy package first"* ]]
  [ ! -s "$TEST_HOME/.config/hypr/bindings.conf" ]
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

@test "bootstrap-omarchy: rejects an empty package list before mutation" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --packages="   "

  [ "$status" -eq 1 ]
  [[ "$output" == *"requires at least one package"* ]]
  assert_mock_not_called sudo
}

@test "bootstrap-omarchy: rejects an unknown package before mutation" {
  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --packages "git not-a-package"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown stow package: not-a-package"* ]]
  assert_mock_not_called sudo
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

@test "bootstrap-omarchy: a stow conflict on one package does not abort the rest of the script" {
  # Real files already at the target (e.g. Omarchy's own ~/.config/nvim) are
  # a per-package stow conflict, not a reason to skip unrelated later steps
  # like keyd/hypr/mise — this is what actually happened on a real run.
  # shellcheck disable=SC2016
  mock_command_with_script "stow" '
for arg in "$@"; do
  if [[ "$arg" == "nvim" ]]; then
    echo "WARNING! stowing nvim would cause conflicts" >&2
    exit 1
  fi
done
exit 0
'

  run env \
    HOME="$TEST_HOME" \
    OSTYPE="linux-gnu" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$BOOTSTRAP_SCRIPT" --no-input --skip-pacman --skip-keyd --skip-hypr --skip-mise --packages "git nvim tmux"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Stow reported conflicts"* ]]
  [[ "$output" == *"Continuing with the rest of bootstrap"* ]]
  [[ "$output" == *"Bootstrap complete!"* ]]
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
