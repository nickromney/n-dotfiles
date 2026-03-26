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

  cp "$REPO_ROOT/setup-work-mac.sh" "$TEST_REPO/setup-work-mac.sh"
  cp "$REPO_ROOT/scripts/setup-mac-lib.sh" "$TEST_REPO/scripts/setup-mac-lib.sh"
  chmod +x "$TEST_REPO/setup-work-mac.sh"

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

  cat >"$TEST_REPO/_configs/host/work.yaml" <<'EOF'
tools: {}
EOF

  cat >"$TEST_REPO/_macos/work.yaml" <<'EOF'
finder:
  show_hidden_files: true
EOF

  mock_command "uname" 0 "Darwin"
  mock_command "brew" 0 ""
  mock_command "yq" 0 ""
  mock_command "stow" 0 ""

  export PATH="$MOCK_BIN_DIR:/usr/bin:/bin"
  cd "$TEST_REPO" || return 1
}

teardown() {
  teardown_mocks
  rm -rf "$TEST_REPO"
}

@test "setup-work-mac: help output includes examples" {
  run ./setup-work-mac.sh --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Examples:"* ]]
  [[ "$output" == *"--skip-profile-packages"* ]]
}

@test "setup-work-mac: dry-run forwards non-interactive flags to nested commands" {
  run ./setup-work-mac.sh --dry-run --no-input

  [ "$status" -eq 0 ]
  [[ "$output" == *"Essential tools already installed"* ]]
  grep -q 'CONFIG_FILES=shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common ARGS=-d' "$CALLS_DIR/install.calls"
  grep -q 'CONFIG_FILES=host/work ARGS=-d' "$CALLS_DIR/install.calls"
  grep -q 'CONFIG_FILES= ARGS=-d -s' "$CALLS_DIR/install.calls"
  grep -q -- '--dry-run --no-input _macos/work.yaml' "$CALLS_DIR/macos.calls"
  [ ! -f "$CALLS_DIR/bootstrap.calls" ]
}

@test "setup-work-mac: skip flags suppress optional steps" {
  run ./setup-work-mac.sh --dry-run --skip-profile-packages --skip-macos --skip-vscode

  [ "$status" -eq 0 ]
  grep -q 'CONFIG_FILES=shared/shell shared/git shared/search shared/file-tools shared/data-tools shared/network shared/neovim host/common ARGS=-d' "$CALLS_DIR/install.calls"
  run grep -q 'CONFIG_FILES=host/work' "$CALLS_DIR/install.calls"
  [ "$status" -ne 0 ]
  [ ! -f "$CALLS_DIR/macos.calls" ]
}
