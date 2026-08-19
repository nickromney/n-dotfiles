#!/usr/bin/env bats

load helpers/mocks.bash

setup() {
  setup_mocks

  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CHECK_SCRIPT="$REPO_ROOT/scripts/check-1password-dev-tools.sh"
  export TEST_TMP_DIR
  TEST_TMP_DIR="$(mktemp -d)"
  export FAKE_SIGNER="$TEST_TMP_DIR/op-ssh-sign"
  echo '#!/usr/bin/env bash' >"$FAKE_SIGNER"
  chmod +x "$FAKE_SIGNER"
}

teardown() {
  teardown_mocks
  rm -rf "$TEST_TMP_DIR"
}

mock_op_signed_in() {
  # shellcheck disable=SC2016
  mock_command_with_script "op" '
case "$1" in
  account)
    echo "URL,EMAIL,USER_UUID"
    echo "my.1password.com,nick@example.com,ABC123"
    exit 0
    ;;
  *) exit 1 ;;
esac
'
}

mock_op_signed_out() {
  # shellcheck disable=SC2016
  mock_command_with_script "op" '
case "$1" in
  account) exit 0 ;;
  *) exit 1 ;;
esac
'
}

@test "check-1password-dev-tools: reports failure when op CLI is absent" {
  # Even on hosts where op is genuinely installed system-wide (e.g. Arch's
  # 1password-cli package puts it in /usr/bin), this must still exclude it.
  run env PATH="$(path_excluding op)" "$CHECK_SCRIPT"

  [[ "$output" == *"FAIL 1Password CLI (op) not found on PATH"* ]]
  [ "$status" -gt 0 ]
}

@test "check-1password-dev-tools: reports not-signed-in when op has no account" {
  mock_op_signed_out

  run env PATH="$MOCK_BIN_DIR:/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER"

  [[ "$output" == *"OK   1Password CLI (op) found"* ]]
  [[ "$output" == *"FAIL 1Password CLI has no signed-in account"* ]]
}

@test "check-1password-dev-tools: reports signed-in account" {
  mock_op_signed_in

  run env PATH="$MOCK_BIN_DIR:/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER"

  [[ "$output" == *"OK   1Password CLI has a signed-in account"* ]]
}

@test "check-1password-dev-tools: finds the SSH agent socket at a candidate path" {
  local gitconfig="$TEST_TMP_DIR/gitconfig"
  mock_op_signed_in
  git config --file "$gitconfig" gpg.ssh.program "$FAKE_SIGNER"
  mkdir -p "$TEST_TMP_DIR/.1password"
  if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
    ln -s "$SSH_AUTH_SOCK" "$TEST_TMP_DIR/.1password/agent.sock"
  else
    python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
" "$TEST_TMP_DIR/.1password/agent.sock"
  fi

  run env HOME="$TEST_TMP_DIR" SSH_AUTH_SOCK="" PATH="$MOCK_BIN_DIR:/usr/bin:/bin" \
    "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER" --wrapper-path "$FAKE_SIGNER" \
    --gitconfig "$gitconfig"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OK   1Password SSH agent socket found: $TEST_TMP_DIR/.1password/agent.sock"* ]]
}

@test "check-1password-dev-tools: reports missing SSH agent socket" {
  local empty_home
  local gitconfig="$TEST_TMP_DIR/gitconfig"
  empty_home="$(mktemp -d)"
  mock_op_signed_in
  git config --file "$gitconfig" gpg.ssh.program "$FAKE_SIGNER"

  run env HOME="$empty_home" XDG_RUNTIME_DIR="$empty_home/run" SSH_AUTH_SOCK="" \
    PATH="$MOCK_BIN_DIR:/usr/bin:/bin" "$CHECK_SCRIPT" \
    --signer-path "$FAKE_SIGNER" --wrapper-path "$FAKE_SIGNER" --gitconfig "$gitconfig"

  [ "$status" -gt 0 ]
  [[ "$output" == *"FAIL 1Password SSH agent socket not found"* ]]

  rm -rf "$empty_home"
}

@test "check-1password-dev-tools: finds the signer binary at the given path" {
  run env PATH="/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER"

  [[ "$output" == *"OK   op-ssh-sign binary found: $FAKE_SIGNER"* ]]
}

@test "check-1password-dev-tools: reports missing signer binary" {
  run env PATH="/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$TEST_TMP_DIR/does-not-exist"

  [[ "$output" == *"FAIL op-ssh-sign binary not found at $TEST_TMP_DIR/does-not-exist"* ]]
}

@test "check-1password-dev-tools: finds the wrapper shim at the given path" {
  run env PATH="/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER" --wrapper-path "$FAKE_SIGNER"

  [[ "$output" == *"OK   op-ssh-sign shim found: $FAKE_SIGNER"* ]]
}

@test "check-1password-dev-tools: reports missing wrapper shim with a stow hint" {
  run env PATH="/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER" --wrapper-path "$TEST_TMP_DIR/does-not-exist"

  [[ "$output" == *"FAIL op-ssh-sign shim not found at $TEST_TMP_DIR/does-not-exist"* ]]
  [[ "$output" == *"Stow the git package: ./stow.sh git"* ]]
}

@test "check-1password-dev-tools: flags a gitconfig signer path mismatch and suggests a fix" {
  local gitconfig="$TEST_TMP_DIR/gitconfig"
  git config --file "$gitconfig" gpg.ssh.program "/some/other/path/op-ssh-sign"

  run env PATH="/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER" --wrapper-path "$FAKE_SIGNER" --gitconfig "$gitconfig"

  [[ "$output" == *"FAIL $gitconfig gpg.ssh.program is '/some/other/path/op-ssh-sign', expected '$FAKE_SIGNER'"* ]]
  [[ "$output" == *"Fix: git config --file '$gitconfig' gpg.ssh.program '$FAKE_SIGNER'"* ]]
}

@test "check-1password-dev-tools: passes when gitconfig signer path matches the wrapper" {
  local gitconfig="$TEST_TMP_DIR/gitconfig"
  git config --file "$gitconfig" gpg.ssh.program "$FAKE_SIGNER"

  run env PATH="/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER" --wrapper-path "$FAKE_SIGNER" --gitconfig "$gitconfig"

  [[ "$output" == *"OK   $gitconfig gpg.ssh.program points at the portable shim: $FAKE_SIGNER"* ]]
}

@test "check-1password-dev-tools: default expected gitconfig value is the literal ~/.local/bin/op-ssh-sign" {
  local gitconfig="$TEST_TMP_DIR/gitconfig"
  # shellcheck disable=SC2088 # Intentionally unexpanded; matches what git config stores literally.
  git config --file "$gitconfig" gpg.ssh.program '~/.local/bin/op-ssh-sign'

  run env PATH="/usr/bin:/bin" "$CHECK_SCRIPT" --signer-path "$FAKE_SIGNER" --gitconfig "$gitconfig"

  [[ "$output" == *"OK   $gitconfig gpg.ssh.program points at the portable shim: ~/.local/bin/op-ssh-sign"* ]]
}

@test "check-1password-dev-tools: help output includes examples" {
  run "$CHECK_SCRIPT" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Examples:"* ]]
}
