#!/usr/bin/env bats
setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_TMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TMP_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export MISE_GLOBAL_CONFIG_FILE="$XDG_CONFIG_HOME/mise/config.toml"
  export MISE_CALLS="$TEST_TMP_DIR/calls"
  mkdir -p "$XDG_CONFIG_HOME/mise" "$TEST_TMP_DIR/bin"
  ln -s "$REPO_ROOT/mise/.config/mise/config.toml" "$MISE_GLOBAL_CONFIG_FILE"
  cat > "$TEST_TMP_DIR/bin/mise" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MISE_CALLS"
[[ "$*" != 'cache path' ]] || printf '%s\n' "$HOME/cache"
if [[ "${FAIL_PRUNE:-0}" == 1 && "$*" == *'prune'* ]]; then exit 1; fi
exit 0
MOCK
  chmod +x "$TEST_TMP_DIR/bin/mise"
  export PATH="$TEST_TMP_DIR/bin:$PATH"
}
teardown() { rm -rf "$TEST_TMP_DIR"; }

@test "mise cleanup defaults to preview and help documents tracked-config limits" {
  run "$REPO_ROOT/scripts/cleanup-mise.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"untracked projects"* ]]
  [[ "$output" == *"Examples:"* ]]
  run "$REPO_ROOT/scripts/cleanup-mise.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$MISE_CALLS")" = $'prune --tools --dry-run\ncache path' ]
}
@test "mise all delegates cleanup without uninstalling all tools" {
  run "$REPO_ROOT/scripts/cleanup-mise.sh" --execute --all --no-input
  [ "$status" -eq 0 ]
  [ "$(cat "$MISE_CALLS")" = $'prune --tools --dry-run\ncache path\n--yes prune --tools\n--yes cache clear' ]
}
@test "mise cache-only works without repo stow and never prunes" {
  rm "$MISE_GLOBAL_CONFIG_FILE"
  run "$REPO_ROOT/scripts/cleanup-mise.sh" --execute --cache-only
  [ "$status" -eq 0 ]
  [ "$(cat "$MISE_CALLS")" = $'cache path\n--yes cache clear' ]
}
@test "mise pruning refuses unstowed global config" {
  rm "$MISE_GLOBAL_CONFIG_FILE"
  run "$REPO_ROOT/scripts/cleanup-mise.sh" --execute --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"not stowed"* ]]
  [ ! -e "$MISE_CALLS" ]
}
@test "mise failed preview prevents actual pruning and cache cleanup" {
  run env FAIL_PRUNE=1 "$REPO_ROOT/scripts/cleanup-mise.sh" --execute --all
  [ "$status" -ne 0 ]
  [ "$(cat "$MISE_CALLS")" = 'prune --tools --dry-run' ]
}
@test "mise invalid scopes are rejected" {
  for args in '--execute' '--all --cache-only' '--prune-only --cache-only' '--execute --dry-run' '--wat'; do
    # shellcheck disable=SC2086
    run "$REPO_ROOT/scripts/cleanup-mise.sh" $args
    [ "$status" -ne 0 ]
    [ ! -e "$MISE_CALLS" ]
  done
}
