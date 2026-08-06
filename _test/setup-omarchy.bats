#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_TMP_DIR
  TEST_TMP_DIR="$(mktemp -d)"
  mkdir -p "$TEST_TMP_DIR/bin" "$TEST_TMP_DIR/home"

  cat >"$TEST_TMP_DIR/bin/uname" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-s" ]]; then
  echo Linux
else
  /usr/bin/uname "$@"
fi
EOF
  chmod +x "$TEST_TMP_DIR/bin/uname"

  cat >"$TEST_TMP_DIR/bin/pacman" <<'EOF'
#!/usr/bin/env bash
echo "pacman should not run during a dry run" >&2
exit 1
EOF
  chmod +x "$TEST_TMP_DIR/bin/pacman"
}

teardown() {
  rm -rf "$TEST_TMP_DIR"
}

@test "setup-omarchy: dry-run previews the Arch flow without mutating" {
  run env \
    HOME="$TEST_TMP_DIR/home" \
    PATH="$TEST_TMP_DIR/bin:/usr/bin:/bin" \
    "$REPO_ROOT/setup-omarchy.sh" --dry-run --no-input

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running in dry-run mode"* ]]
  [[ "$output" == *"sudo pacman -S --needed --noconfirm git stow keyd mise"* ]]
  [[ "$output" == *"Stowing personal layers: zsh nvim tmux mise codex claude agents omarchy"* ]]
  [[ "$output" == *"Would add the Hyper bindings include"* ]]
  [[ "$output" == *"Omarchy setup dry run complete"* ]]
}

@test "setup-omarchy: rejects unknown options" {
  run "$REPO_ROOT/setup-omarchy.sh" --skip-vscode

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --skip-vscode"* ]]
}
