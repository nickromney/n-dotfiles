#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  export TEST_HOME
  mkdir -p "$TEST_HOME" "$BATS_TEST_TMPDIR/bin"
  if ! command -v bun >/dev/null 2>&1 ||
    [[ ! -d "$REPO_ROOT/scripts/node_modules/puppeteer-core" ]]; then
    skip "browser CLI requires existing Bun and local dependencies"
  fi
  cd "$BATS_TEST_TMPDIR" || return 1
}

@test "browser start treats shell substitutions in profile paths literally" {
  local profile_dir="$BATS_TEST_TMPDIR/profile-\$(touch injected)"

  run env HOME="$TEST_HOME" bun "$REPO_ROOT/scripts/browser-tools.ts" start \
    --profile-dir "$profile_dir" --chrome-path "$BATS_TEST_TMPDIR/missing-chrome"

  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/injected" ]
  [ -d "$profile_dir" ]
}

@test "browser profile copy preserves unrelated destination files" {
  command -v rsync >/dev/null 2>&1 || skip "rsync is required for profile copying"
  local source="$TEST_HOME/Library/Application Support/Google/Chrome"
  local profile_dir="$BATS_TEST_TMPDIR/profile"
  mkdir -p "$source/Default" "$profile_dir"
  printf '%s\n' 'profile preferences' > "$source/Default/Preferences"
  printf '%s\n' 'keep this file' > "$profile_dir/unrelated.txt"

  run env HOME="$TEST_HOME" bun "$REPO_ROOT/scripts/browser-tools.ts" start \
    --profile --profile-dir "$profile_dir" --chrome-path "$BATS_TEST_TMPDIR/missing-chrome"

  [ "$status" -ne 0 ]
  [ "$(cat "$profile_dir/unrelated.txt")" = 'keep this file' ]
  [ "$(cat "$profile_dir/Default/Preferences")" = 'profile preferences' ]
}
