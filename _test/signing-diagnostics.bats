#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export SIGNING_REPO="$BATS_TEST_TMPDIR/repository"
  export SSH_AUTH_SOCK="$BATS_TEST_TMPDIR/selected-agent.sock"
  mkdir -p "$HOME" "$SIGNING_REPO" "$BATS_TEST_TMPDIR/bin"
  git init -q "$SIGNING_REPO"
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/key"
  git -C "$SIGNING_REPO" config user.signingkey "$(cat "$BATS_TEST_TMPDIR/key.pub")"
  git -C "$SIGNING_REPO" config gpg.format ssh
  export DIAGNOSTIC_FINGERPRINT
  DIAGNOSTIC_FINGERPRINT="$(ssh-keygen -lf "$BATS_TEST_TMPDIR/key.pub" | awk '{print $2}')"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  cat > "$BATS_TEST_TMPDIR/bin/ssh-add" <<'MOCK'
#!/bin/sh
echo "256 ${OFFERED_FINGERPRINT:-$DIAGNOSTIC_FINGERPRINT} test-key (ED25519)"
MOCK
  cat > "$BATS_TEST_TMPDIR/bin/op" <<'MOCK'
#!/bin/sh
touch "$HOME/op-was-called"
exit 1
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh-add" "$BATS_TEST_TMPDIR/bin/op"
}

@test "signing diagnostics use repository overrides without invoking op or creating commits" {
  printf '[user]\n signingkey = ssh-ed25519 invalid-global-key\n' > "$HOME/.gitconfig"
  run "$BATS_TEST_DIRNAME/../scripts/check-1password-dev-tools.sh" --diagnose-signing --repo "$SIGNING_REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$DIAGNOSTIC_FINGERPRINT"* ]]
  [[ "$output" == *"file:.git/config"* ]]
  [[ "$output" == *"Configured signing key is offered"* ]]
  [ ! -e "$HOME/op-was-called" ]
  [ ! -e "$SIGNING_REPO/.git/refs/heads/main" ]
}

@test "signing diagnostics fail when the configured key is absent from the agent" {
  export OFFERED_FINGERPRINT='SHA256:different-key'
  run "$BATS_TEST_DIRNAME/../scripts/check-1password-dev-tools.sh" --diagnose-signing --repo "$SIGNING_REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Configured signing key is absent"* ]]
}
