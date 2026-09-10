#!/usr/bin/env bats

setup() {
  export TEST_ROOT
  TEST_ROOT="$(mktemp -d)"
  export TEST_APP="$TEST_ROOT/Borders.app"
  mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_ROOT/bin"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_APP/Contents/MacOS/borders"
  chmod +x "$TEST_APP/Contents/MacOS/borders"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/pgrep"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/open"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/bin/sleep"
  chmod +x "$TEST_ROOT/bin/"*
}

teardown() { rm -rf "$TEST_ROOT"; }

run_controller() {
  run env \
    BORDERS_APP_HOME="$TEST_APP" \
    BORDERS_BINARY="$TEST_APP/Contents/MacOS/borders" \
    BORDERS_PGREP="$TEST_ROOT/bin/pgrep" \
    BORDERS_OPEN="$TEST_ROOT/bin/open" \
    BORDERS_SLEEP="$TEST_ROOT/bin/sleep" \
    "$BATS_TEST_DIRNAME/../macos-borders/.local/bin/borders" "$@"
}

@test "borders exposes the standalone app commands" {
  run_controller --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"borders on"* ]]
  [[ "$output" == *"borders off"* ]]
  [[ "$output" == *"borders status"* ]]
}

@test "borders dry-run uses the installed app and does not use a daemon" {
  run_controller --dry-run on

  [ "$status" -eq 0 ]
  [[ "$output" == *"Would launch"* ]]
  [[ "$output" == *"Would send: on"* ]]
  [[ "$output" == *"Borders is on"* ]]
}

@test "borders reconcile reloads the standalone app configuration" {
  run_controller --dry-run reconcile

  [ "$status" -eq 0 ]
  [[ "$output" == *"Would send: reconcile"* ]]
  [[ "$output" == *"Borders reconciled"* ]]
}
