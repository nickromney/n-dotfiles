#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_ROOT
  TEST_ROOT="$(mktemp -d)"
  export TEST_HOME="$TEST_ROOT/home"
  export N_BORDERS_TEST_DIR="$TEST_ROOT/state"
  mkdir -p "$TEST_HOME/.local/share/n-borders" "$TEST_ROOT/bin" "$N_BORDERS_TEST_DIR"
  printf 'print("fixture")\n' >"$TEST_HOME/.local/share/n-borders/borders.swift"

  cat >"$TEST_ROOT/bin/swiftc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
mkdir -p "$(dirname "$output")"
touch "$output"
chmod +x "$output"
EOF

  cat >"$TEST_ROOT/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$N_BORDERS_TEST_DIR/launchctl.log"
case "$1" in
  print)
    [[ -f "$N_BORDERS_TEST_DIR/native-loaded" || -f "$N_BORDERS_TEST_DIR/native-running" ]]
    ;;
  bootstrap | kickstart)
    touch "$N_BORDERS_TEST_DIR/native-loaded"
    touch "$N_BORDERS_TEST_DIR/native-running"
    ;;
  bootout)
    rm -f "$N_BORDERS_TEST_DIR/native-loaded"
    rm -f "$N_BORDERS_TEST_DIR/native-running"
    ;;
  enable) ;;
esac
EOF

  cat >"$TEST_ROOT/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-x" && "${2:-}" == "borders" ]]; then
  if [[ -f "$N_BORDERS_TEST_DIR/janky-running" ]]; then
    echo 123
    exit 0
  fi
elif [[ "${1:-}" == "-x" && "${2:-}" == "n-borders-daemon" ]]; then
  if [[ -f "$N_BORDERS_TEST_DIR/native-running" ]]; then
    echo 456
    exit 0
  fi
fi
exit 1
EOF

  cat >"$TEST_ROOT/bin/pkill" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-x" && "${2:-}" == "borders" ]]; then
  rm -f "$N_BORDERS_TEST_DIR/janky-running"
fi
EOF

  cat >"$TEST_ROOT/bin/borders" <<'EOF'
#!/usr/bin/env bash
touch "$N_BORDERS_TEST_DIR/janky-running"
EOF

  cat >"$TEST_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod +x "$TEST_ROOT/bin/"*
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_controller() {
  run env \
    N_BORDERS_HOME="$TEST_HOME" \
    N_BORDERS_SWIFTC="$TEST_ROOT/bin/swiftc" \
    N_BORDERS_LAUNCHCTL="$TEST_ROOT/bin/launchctl" \
    N_BORDERS_PGREP="$TEST_ROOT/bin/pgrep" \
    N_BORDERS_PKILL="$TEST_ROOT/bin/pkill" \
    N_BORDERS_JANKY_BINARY="${N_BORDERS_JANKY_BINARY:-$TEST_ROOT/bin/borders}" \
    N_BORDERS_SLEEP="$TEST_ROOT/bin/sleep" \
    N_BORDERS_UID=501 \
    "$REPO_ROOT/macos-borders/.local/bin/n-borders" "$@"
}

@test "n-borders exposes reversible commands and dry-run" {
  run_controller --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"n-borders on"* ]]
  [[ "$output" == *"n-borders off"* ]]
  [[ "$output" == *"n-borders status"* ]]
  [[ "$output" == *"--dry-run"* ]]

  touch "$N_BORDERS_TEST_DIR/janky-running"
  run_controller --dry-run on

  [ "$status" -eq 0 ]
  [[ "$output" == *"Would build"* ]]
  [[ "$output" == *"Would install LaunchAgent"* ]]
  [[ "$output" == *"Would stop JankyBorders"* ]]
  [ -f "$N_BORDERS_TEST_DIR/janky-running" ]
  [ ! -e "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist" ]
}

@test "n-borders on builds and starts native border before stopping JankyBorders" {
  touch "$N_BORDERS_TEST_DIR/janky-running"

  run_controller on

  [ "$status" -eq 0 ]
  [ -x "$TEST_HOME/.local/bin/n-borders-daemon" ]
  [ -f "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist" ]
  [ -f "$N_BORDERS_TEST_DIR/native-running" ]
  [ ! -f "$N_BORDERS_TEST_DIR/janky-running" ]
  [[ "$output" == *"n-borders is on"* ]]
}

@test "n-borders on replaces a stale loaded native label" {
  touch "$N_BORDERS_TEST_DIR/native-loaded"

  run_controller on

  [ "$status" -eq 0 ]
  [ -f "$N_BORDERS_TEST_DIR/native-running" ]
  bootout_line="$(grep -n 'bootout' "$N_BORDERS_TEST_DIR/launchctl.log" | head -1 | cut -d: -f1)"
  bootstrap_line="$(grep -n 'bootstrap' "$N_BORDERS_TEST_DIR/launchctl.log" | head -1 | cut -d: -f1)"
  [ "$bootout_line" -lt "$bootstrap_line" ]
}

@test "n-borders off restores JankyBorders before unloading native border" {
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  touch "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist"
  touch "$N_BORDERS_TEST_DIR/native-running"

  run_controller off

  [ "$status" -eq 0 ]
  [ -f "$N_BORDERS_TEST_DIR/janky-running" ]
  [ ! -f "$N_BORDERS_TEST_DIR/native-running" ]
  [ ! -e "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist" ]
  [[ "$output" == *"JankyBorders is restored"* ]]
}

@test "n-borders off works without an installed fallback" {
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  touch "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist"
  touch "$N_BORDERS_TEST_DIR/native-running"

  N_BORDERS_JANKY_BINARY="$TEST_ROOT/bin/missing-borders" run_controller off

  [ "$status" -eq 0 ]
  [ ! -f "$N_BORDERS_TEST_DIR/native-running" ]
  [ ! -e "$TEST_HOME/Library/LaunchAgents/com.nickromney.n-borders.plist" ]
  [[ "$output" == *"no fallback border backend is running"* ]]
}

@test "n-borders rejects unknown commands" {
  run_controller wat

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command: wat"* ]]
}
