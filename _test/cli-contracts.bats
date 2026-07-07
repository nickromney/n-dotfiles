#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_TMP_DIR
  TEST_TMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP_DIR"
}

assert_help_contract() {
  local script="$1"

  run "$REPO_ROOT/$script" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Examples:"* ]]
}

write_mock_slicer_mac() {
  mkdir -p "$TEST_TMP_DIR/bin"
  cat >"$TEST_TMP_DIR/bin/slicer-mac" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SLICER_MAC_CALL_LOG"
EOF
  chmod +x "$TEST_TMP_DIR/bin/slicer-mac"
}

@test "user-facing scripts expose help with examples" {
  local script
  scripts=(
    "bootstrap.sh"
    "stow.sh"
    "setup-personal-mac.sh"
    "setup-ssh-from-1password.sh"
    "setup-gitconfig-from-1password.sh"
    "_macos/macos.sh"
    "scripts/audit.sh"
    "scripts/audit-harness-guides.sh"
    "scripts/audit-installed.sh"
    "scripts/sync-private-harness-assets.sh"
    "scripts/build-browser-tools.sh"
    "slicer-mac/check-slicer-version.sh"
    "slicer-mac/install-slicer-mac.sh"
    "slicer-mac/remove-slicer-mac.sh"
    "slicer-mac/restart-slicer-mac.sh"
  )

  for script in "${scripts[@]}"; do
    assert_help_contract "$script"
  done
}

@test "restart-slicer-mac: execute restarts tray and daemon as the current user" {
  write_mock_slicer_mac

  run env \
    PATH="$TEST_TMP_DIR/bin:$PATH" \
    SLICER_MAC_CALL_LOG="$TEST_TMP_DIR/slicer-mac-calls.log" \
    "$REPO_ROOT/slicer-mac/restart-slicer-mac.sh" --execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"slicer-mac service restart tray"* ]]
  [[ "$output" == *"slicer-mac service restart daemon"* ]]

  run cat "$TEST_TMP_DIR/slicer-mac-calls.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"service status tray"* ]]
  [[ "$output" == *"service status daemon"* ]]
  [[ "$output" == *"service restart tray"* ]]
  [[ "$output" == *"service restart daemon"* ]]
}

@test "restart-slicer-mac: rejects sudo/root because slicer-mac services are per-user" {
  mkdir -p "$TEST_TMP_DIR/bin"
  cat >"$TEST_TMP_DIR/bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
  echo 0
  exit 0
fi
command id "$@"
EOF
  chmod +x "$TEST_TMP_DIR/bin/id"

  run env PATH="$TEST_TMP_DIR/bin:$PATH" "$REPO_ROOT/slicer-mac/restart-slicer-mac.sh" --execute

  [ "$status" -eq 1 ]
  [[ "$output" == *"do not run this script with sudo"* ]]
  [[ "$output" == *"per-user launchd services"* ]]
  [[ "$output" == *"Run without sudo: ./restart-slicer-mac.sh --execute"* ]]
}

@test "brew-with-policy: help documents tap trust policy without requiring Homebrew" {
  run "$REPO_ROOT/scripts/brew-with-policy.sh" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Homebrew tap trust policy"* ]]
  [[ "$output" == *"HOMEBREW_REQUIRE_TAP_TRUST"* ]]
  [[ "$output" == *"HOMEBREW_NO_REQUIRE_TAP_TRUST"* ]]
  [[ "$output" == *"HOMEBREW_NO_ENV_HINTS"* ]]
  [[ "$output" == *"Examples:"* ]]
}

@test "stow: list mode prints packages without touching the filesystem" {
  run "$REPO_ROOT/stow.sh" --list

  [ "$status" -eq 0 ]
  [[ "$output" == *"zsh"* ]]
  [[ "$output" == *"git"* ]]
  [[ "$output" == *"mise"* ]]
  [[ "$output" != *"vscode"* ]]
}

@test "stow: rejects unknown packages" {
  run "$REPO_ROOT/stow.sh" --dry-run no-such-package

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown stow package: no-such-package"* ]]
}

@test "build-browser-tools: dry-run prints the planned build commands" {
  run "$REPO_ROOT/scripts/build-browser-tools.sh" --dry-run --bin-dir "$TEST_TMP_DIR/bin"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would"* ]]
  [[ "$output" == *"$TEST_TMP_DIR/bin/browser-tools"* ]]
}
