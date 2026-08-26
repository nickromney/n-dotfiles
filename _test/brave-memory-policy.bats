#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_ROOT
  TEST_ROOT="$(mktemp -d)"
  export BRAVE_POLICY_STATE="$TEST_ROOT/policy"
  mkdir -p "$TEST_ROOT/bin"

  cat >"$TEST_ROOT/bin/defaults" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  read)
    [[ -f "$BRAVE_POLICY_STATE" ]] || exit 1
    cat "$BRAVE_POLICY_STATE"
    ;;
  write)
    printf '%s\n' "$5" >"$BRAVE_POLICY_STATE"
    ;;
  delete)
    rm -f "$BRAVE_POLICY_STATE"
    ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$TEST_ROOT/bin/defaults"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_policy() {
  run env \
    BRAVE_POLICY_DEFAULTS="$TEST_ROOT/bin/defaults" \
    BRAVE_POLICY_DOMAIN="com.brave.Browser" \
    BRAVE_POLICY_KEY="TotalMemoryLimitMb" \
    BRAVE_POLICY_STATE="$BRAVE_POLICY_STATE" \
    "$REPO_ROOT/scripts/configure-brave-memory.sh" "$@"
}

@test "Brave memory policy exposes status and dry-run without changing state" {
  run_policy --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"configure-brave-memory.sh on"* ]]
  [[ "$output" == *"--dry-run"* ]]

  run_policy --dry-run on

  [ "$status" -eq 0 ]
  [[ "$output" == *"Would set Brave TotalMemoryLimitMb to 2048 MiB"* ]]
  [ ! -e "$BRAVE_POLICY_STATE" ]
}

@test "Brave memory policy on and off are reversible" {
  run_policy on

  [ "$status" -eq 0 ]
  [ "$(cat "$BRAVE_POLICY_STATE")" = "2048" ]
  [[ "$output" == *"Brave memory policy: 2048 MiB"* ]]

  run_policy off

  [ "$status" -eq 0 ]
  [ ! -e "$BRAVE_POLICY_STATE" ]
  [[ "$output" == *"Brave memory policy: disabled"* ]]
}

@test "Brave memory policy validates limits and commands" {
  run_policy on --limit 1023
  [ "$status" -eq 1 ]
  [[ "$output" == *"at least 1024 MiB"* ]]

  run_policy wat
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command: wat"* ]]
}
