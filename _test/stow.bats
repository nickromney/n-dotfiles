#!/usr/bin/env bats

setup() {
  export TEST_ROOT
  TEST_ROOT="$(mktemp -d)"
  export TEST_HOME="$TEST_ROOT/home"
  export TEST_REPO="$TEST_ROOT/repo"
  mkdir -p "$TEST_HOME" "$TEST_REPO/zsh"
  cp "$BATS_TEST_DIRNAME/../stow.sh" "$TEST_REPO/stow.sh"
  chmod +x "$TEST_REPO/stow.sh"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "stow backup mode preserves an unmanaged dotfile before replacing it" {
  printf '%s\n' 'repository zsh config' > "$TEST_REPO/zsh/.zshrc"
  printf '%s\n' 'previous local zsh config' > "$TEST_HOME/.zshrc"
  local backup_dir="$TEST_ROOT/backups"

  run env HOME="$TEST_HOME" \
    /bin/bash "$TEST_REPO/stow.sh" --backup-conflicts --backup-dir "$backup_dir" zsh

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.zshrc" ]
  [ "$(cat "$TEST_HOME/.zshrc")" = "repository zsh config" ]
  [ "$(cat "$backup_dir/.zshrc")" = "previous local zsh config" ]
  [[ "$output" == *"Backed up .zshrc"* ]]
}

@test "stow backup mode uses the XDG state directory by default" {
  printf '%s\n' 'repository zsh config' > "$TEST_REPO/zsh/.zshrc"
  printf '%s\n' 'previous local zsh config' > "$TEST_HOME/.zshrc"
  local state_dir="$TEST_ROOT/state"

  run env HOME="$TEST_HOME" XDG_STATE_HOME="$state_dir" \
    "$TEST_REPO/stow.sh" --backup-conflicts zsh

  [ "$status" -eq 0 ]
  run find "$state_dir/n-dotfiles/stow-backups" -type f -name .zshrc -exec cat {} \;
  [ "$status" -eq 0 ]
  [ "$output" = "previous local zsh config" ]
}

@test "stow rejects dry-run recovery without moving a conflict" {
  printf '%s\n' 'repository zsh config' > "$TEST_REPO/zsh/.zshrc"
  printf '%s\n' 'unmanaged zsh config' > "$TEST_HOME/.zshrc"

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" --dry-run --backup-conflicts zsh

  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_HOME/.zshrc")" = "unmanaged zsh config" ]
  [[ "$output" == *"--dry-run and --backup-conflicts cannot be used together"* ]]
}

@test "stow detects all conflicts before changing any package" {
  mkdir -p "$TEST_REPO/aerospace/.config/aerospace"
  printf '%s\n' 'aerospace config' > "$TEST_REPO/aerospace/.config/aerospace/aerospace.toml"
  printf '%s\n' 'repository zsh config' > "$TEST_REPO/zsh/.zshrc"
  printf '%s\n' 'unmanaged zsh config' > "$TEST_HOME/.zshrc"

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" aerospace zsh

  [ "$status" -eq 1 ]
  [ ! -e "$TEST_HOME/.config" ]
  [ ! -L "$TEST_HOME/.config" ]
  [ "$(cat "$TEST_HOME/.zshrc")" = "unmanaged zsh config" ]
}

@test "stow restores staged backups when recovery preflight fails" {
  mkdir -p "$TEST_REPO/mise/.config/mise"
  printf '%s\n' 'repository zsh config' > "$TEST_REPO/zsh/.zshrc"
  printf '%s\n' 'repository mise config' > "$TEST_REPO/mise/.config/mise/config.toml"
  printf '%s\n' 'unmanaged zsh config' > "$TEST_HOME/.zshrc"
  printf '%s\n' 'blocks the .config directory' > "$TEST_HOME/.config"
  local backup_dir="$TEST_ROOT/backups"

  run env HOME="$TEST_HOME" \
    "$TEST_REPO/stow.sh" --backup-conflicts --backup-dir "$backup_dir" zsh mise

  [ "$status" -eq 1 ]
  [ ! -L "$TEST_HOME/.zshrc" ]
  [ "$(cat "$TEST_HOME/.zshrc")" = "unmanaged zsh config" ]
  [ ! -e "$backup_dir/.zshrc" ]
}
