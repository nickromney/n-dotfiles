#!/usr/bin/env bats

load helpers/mocks.bash

setup() {
  setup_mocks

  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_REPO
  TEST_REPO="$(mktemp -d)"
  export CALLS_DIR="$TEST_REPO/.calls"

  mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/_configs/host" "$TEST_REPO/_macos" "$CALLS_DIR"

  cp "$REPO_ROOT/setup-personal-mac.sh" "$TEST_REPO/setup-personal-mac.sh"
  cp "$REPO_ROOT/scripts/setup-mac-lib.sh" "$TEST_REPO/scripts/setup-mac-lib.sh"
  chmod +x "$TEST_REPO/setup-personal-mac.sh"

  cat >"$TEST_REPO/install.sh" <<'EOF'
#!/usr/bin/env bash
echo "CONFIG_FILES=${CONFIG_FILES-} ARGS=$*" >>"$CALLS_DIR/install.calls"
exit 0
EOF
  chmod +x "$TEST_REPO/install.sh"

  cat >"$TEST_REPO/bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$CALLS_DIR/bootstrap.calls"
exit 0
EOF
  chmod +x "$TEST_REPO/bootstrap.sh"

  cat >"$TEST_REPO/_macos/macos.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$CALLS_DIR/macos.calls"
exit 0
EOF
  chmod +x "$TEST_REPO/_macos/macos.sh"

  cat >"$TEST_REPO/setup-ssh-from-1password.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$CALLS_DIR/ssh.calls"
exit 0
EOF
  chmod +x "$TEST_REPO/setup-ssh-from-1password.sh"

  cat >"$TEST_REPO/_configs/host/personal.yaml" <<'EOF'
tools: {}
EOF

  cat >"$TEST_REPO/_configs/host/manual-check.yaml" <<'EOF'
tools: {}
EOF

  cat >"$TEST_REPO/_macos/personal.yaml" <<'EOF'
finder:
  show_hidden_files: true
EOF

  mock_command "uname" 0 "Darwin"
  mock_command "brew" 0 ""
  mock_command "yq" 0 ""
  mock_command "stow" 0 ""
  mock_command "op" 0 ""

  export PATH="$MOCK_BIN_DIR:/usr/bin:/bin"
  cd "$TEST_REPO" || return 1
}

teardown() {
  teardown_mocks
  rm -rf "$TEST_REPO"
}

@test "setup-personal-mac: dry-run forwards no-input to SSH setup" {
  run ./setup-personal-mac.sh --dry-run --no-input --skip-vscode

  [ "$status" -eq 0 ]
  grep -q 'CONFIG_FILES=host/manual-check ARGS=-d' "$CALLS_DIR/install.calls"
  grep -q -- '--profile personal --dry-run --no-input' "$CALLS_DIR/ssh.calls"
  grep -q -- '--dry-run --no-input _macos/personal.yaml' "$CALLS_DIR/macos.calls"
}

@test "setup-personal-mac: skip flags suppress manual-check and SSH steps" {
  run ./setup-personal-mac.sh --dry-run --skip-manual-check --skip-ssh --skip-vscode

  [ "$status" -eq 0 ]
  run grep -q 'CONFIG_FILES=host/manual-check' "$CALLS_DIR/install.calls"
  [ "$status" -ne 0 ]
  [ ! -f "$CALLS_DIR/ssh.calls" ]
}
