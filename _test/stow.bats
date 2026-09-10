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

@test "stow is idempotent without unlinking correct links" {
  printf '%s\n' 'repository zsh config' > "$TEST_REPO/zsh/.zshrc"

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" zsh
  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.zshrc" ]

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" zsh
  [ "$status" -eq 0 ]
  [[ "$output" != *"UNLINK:"* ]]
  [[ "$output" != *"LINK:"* ]]
}

@test "stow restow mode remains explicit" {
  printf '%s\n' 'repository zsh config' > "$TEST_REPO/zsh/.zshrc"
  env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" zsh >/dev/null

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" --restow zsh

  [ "$status" -eq 0 ]
  [[ "$output" == *"UNLINK: .zshrc"* ]]
  [[ "$output" == *"LINK: .zshrc"* ]]
}

@test "stow list exposes macOS packages only on Darwin" {
  local mock_bin="$TEST_ROOT/bin"
  mkdir -p "$mock_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'echo Darwin' >"$mock_bin/uname"
  chmod +x "$mock_bin/uname"

  run env PATH="$mock_bin:$PATH" "$TEST_REPO/stow.sh" --list

  [ "$status" -eq 0 ]
  [[ "$output" == *"aerospace"* ]]
  [[ "$output" == *"audio-priority-bar"* ]]
  [[ "$output" != *"omarchy"* ]]
}

@test "stow list excludes macOS packages on Linux" {
  local mock_bin="$TEST_ROOT/bin"
  mkdir -p "$mock_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'echo Linux' >"$mock_bin/uname"
  chmod +x "$mock_bin/uname"

  run env PATH="$mock_bin:$PATH" "$TEST_REPO/stow.sh" --list

  [ "$status" -eq 0 ]
  [[ "$output" != *"aerospace"* ]]
  [[ "$output" != *"audio-priority-bar"* ]]
  [[ "$output" == *"omarchy"* ]]
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

@test "stow backup mode leaves package-local ignored files untouched" {
  mkdir -p "$TEST_REPO/codex/.codex/rules" "$TEST_HOME/.codex"
  printf '%s\n' 'config\.toml' > "$TEST_REPO/codex/.stow-local-ignore"
  printf '%s\n' 'repository placeholder' > "$TEST_REPO/codex/.codex/config.toml"
  printf '%s\n' 'repository rule' > "$TEST_REPO/codex/.codex/rules/default.rules"
  printf '%s\n' 'live machine config' > "$TEST_HOME/.codex/config.toml"
  local backup_dir="$TEST_ROOT/backups"

  run env HOME="$TEST_HOME" \
    "$TEST_REPO/stow.sh" --backup-conflicts --backup-dir "$backup_dir" codex

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/.codex/config.toml")" = "live machine config" ]
  [ ! -e "$backup_dir/.codex/config.toml" ]
  [ -L "$TEST_HOME/.codex/rules" ]
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

@test "stow removes the legacy n-borders integration after stowing macos-borders" {
  local mock_bin="$TEST_ROOT/bin"
  local launchctl_log="$TEST_ROOT/launchctl.log"
  mkdir -p \
    "$mock_bin" \
    "$TEST_REPO/macos-borders/.config/borders" \
    "$TEST_REPO/macos-borders/.local/bin" \
    "$TEST_HOME/.config/n-borders" \
    "$TEST_HOME/.local/bin" \
    "$TEST_HOME/.local/share/n-borders" \
    "$TEST_HOME/Library/LaunchAgents"
  printf '%s\n' '# config' > "$TEST_REPO/macos-borders/.config/borders/borders.conf"
  printf '%s\n' '#!/usr/bin/env bash' > "$TEST_REPO/macos-borders/.local/bin/borders"
  chmod +x "$TEST_REPO/macos-borders/.local/bin/borders"

  ln -s "$TEST_REPO/macos-borders/.config/n-borders/borders.conf" \
    "$TEST_HOME/.config/n-borders/borders.conf"
  ln -s "$TEST_REPO/macos-borders/.local/bin/n-borders" \
    "$TEST_HOME/.local/bin/n-borders"
  ln -s "$TEST_REPO/macos-borders/.local/share/n-borders/borders.swift" \
    "$TEST_HOME/.local/share/n-borders/borders.swift"
  printf '%s\n' 'old daemon' > "$TEST_HOME/.local/bin/n-borders-daemon"
  cat > "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist" <<'EOF'
<key>Label</key><string>com.nickromney.n-borders</string>
<string>$HOME/.local/bin/n-borders-daemon</string>
EOF
  cat > "$mock_bin/uname" <<'EOF'
#!/usr/bin/env bash
echo Darwin
EOF
  cat > "$mock_bin/launchctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$launchctl_log"
EOF
  chmod +x "$mock_bin/uname" "$mock_bin/launchctl"

  run env \
    HOME="$TEST_HOME" \
    PATH="$mock_bin:$PATH" \
    STOW_LAUNCHCTL_CMD="$mock_bin/launchctl" \
    STOW_UID=501 \
    "$TEST_REPO/stow.sh" --dry-run macos-borders

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.config/n-borders/borders.conf" ]
  [ -f "$TEST_HOME/.local/bin/n-borders-daemon" ]
  [ -f "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist" ]
  [[ "$output" == *"Would remove $TEST_HOME/.local/bin/n-borders"* ]]
  [[ "$output" == *"Would unload gui/501/com.nickromney.n-borders"* ]]

  run env \
    HOME="$TEST_HOME" \
    PATH="$mock_bin:$PATH" \
    STOW_LAUNCHCTL_CMD="$mock_bin/launchctl" \
    STOW_UID=501 \
    "$TEST_REPO/stow.sh" macos-borders

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.config/borders" ]
  [ -f "$TEST_HOME/.config/borders/borders.conf" ]
  [ -L "$TEST_HOME/.local/bin/borders" ]
  [ ! -e "$TEST_HOME/.config/n-borders/borders.conf" ]
  [ ! -e "$TEST_HOME/.local/bin/n-borders" ]
  [ ! -e "$TEST_HOME/.local/share/n-borders/borders.swift" ]
  [ ! -e "$TEST_HOME/.local/bin/n-borders-daemon" ]
  [ ! -e "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist" ]
  [ "$(cat "$launchctl_log")" = "bootout gui/501/com.nickromney.n-borders" ]
}
