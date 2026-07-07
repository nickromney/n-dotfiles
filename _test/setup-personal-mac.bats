#!/usr/bin/env bats

load helpers/mocks.bash

setup() {
  setup_mocks

  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_REPO
  TEST_REPO="$(mktemp -d)"
  export CALLS_DIR="$TEST_REPO/.calls"

  mkdir -p "$TEST_REPO/_macos" "$CALLS_DIR"

  cp "$REPO_ROOT/setup-personal-mac.sh" "$TEST_REPO/setup-personal-mac.sh"
  chmod +x "$TEST_REPO/setup-personal-mac.sh"

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

  cat >"$TEST_REPO/_macos/personal.yaml" <<'EOF'
finder:
  show_hidden_files: true
EOF

  mock_command "uname" 0 "Darwin"
  mock_command "op" 0 ""

  export PATH="$MOCK_BIN_DIR:/usr/bin:/bin"
  cd "$TEST_REPO" || return 1
}

teardown() {
  teardown_mocks
  rm -rf "$TEST_REPO"
}

@test "setup-personal-mac: help output includes examples" {
  run ./setup-personal-mac.sh --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Examples:"* ]]
  [[ "$output" == *"--no-input"* ]]
}

@test "setup-personal-mac: dry-run forwards flags to bootstrap, macOS, and SSH steps" {
  run ./setup-personal-mac.sh --dry-run --no-input

  [ "$status" -eq 0 ]
  grep -q -- '--dry-run --no-input' "$CALLS_DIR/bootstrap.calls"
  grep -q -- '--dry-run --no-input personal.yaml' "$CALLS_DIR/macos.calls"
  grep -q -- '--profile personal --dry-run --no-input' "$CALLS_DIR/ssh.calls"
}

@test "setup-personal-mac: skip flags suppress bootstrap, macOS, and SSH steps" {
  run ./setup-personal-mac.sh --dry-run --skip-bootstrap --skip-macos --skip-ssh

  [ "$status" -eq 0 ]
  [ ! -f "$CALLS_DIR/bootstrap.calls" ]
  [ ! -f "$CALLS_DIR/macos.calls" ]
  [ ! -f "$CALLS_DIR/ssh.calls" ]
}

@test "setup-personal-mac: unknown option fails with usage" {
  run ./setup-personal-mac.sh --skip-vscode

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --skip-vscode"* ]]
}
