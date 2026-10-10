#!/usr/bin/env bats
setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_TMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TMP_DIR/home with spaces"
  export XDG_CACHE_HOME="$TEST_TMP_DIR/cache"
  mkdir -p "$HOME" "$XDG_CACHE_HOME/selenium" "$XDG_CACHE_HOME/huggingface" "$HOME/.factory/logs" "$HOME/.omlx/models" "$HOME/.yarn/berry/cache" "$HOME/.yarn/berry/other" "$HOME/.codex/sessions"
  touch "$XDG_CACHE_HOME/selenium/download" "$XDG_CACHE_HOME/huggingface/model" "$HOME/.factory/logs/log" "$HOME/.factory/settings.json" "$HOME/.omlx/models/model" "$HOME/.yarn/berry/cache/package" "$HOME/.yarn/berry/other/keep" "$HOME/.codex/sessions/keep"
}
teardown() { rm -rf "$TEST_TMP_DIR"; }

@test "storage help and list explain scopes and never delete" {
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Examples:"* ]]
  [[ "$output" == *"excluded from --all"* ]]
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.factory"* ]]
  [ -f "$HOME/.factory/settings.json" ]
}
@test "storage default preview leaves caches intact and excludes optional data" {
  run "$REPO_ROOT/scripts/cleanup-storage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No changes made"* ]]
  [[ "$output" != *"[huggingface]"* ]]
  [[ "$output" != *"[factory-data]"* ]]
  [ -f "$XDG_CACHE_HOME/selenium/download" ]
}
@test "storage all removes rebuildable caches and preserves models histories settings and tools" {
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --execute --all --no-input
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CACHE_HOME/selenium" ]
  [ ! -e "$HOME/.yarn/berry/cache" ]
  [ -f "$HOME/.yarn/berry/other/keep" ]
  [ -f "$HOME/.codex/sessions/keep" ]
  [ -f "$XDG_CACHE_HOME/huggingface/model" ]
  [ -f "$HOME/.omlx/models/model" ]
  [ -f "$HOME/.factory/settings.json" ]
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --execute --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to clean"* ]]
}
@test "storage explicit targets remove only selected data including repeated names" {
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --execute --target factory-logs --target factory-logs --target huggingface
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.factory/logs" ]
  [ ! -e "$XDG_CACHE_HOME/huggingface" ]
  [ -f "$HOME/.factory/settings.json" ]
  [ -f "$XDG_CACHE_HOME/selenium/download" ]
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --execute --target factory-data
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.factory" ]
}
@test "storage rejects invalid and conflicting selections before deletion" {
  for args in '--execute' '--target' '--target ../factory' '--execute --target selenium --target unknown' '--all --target selenium' '--report --execute --all' '--list --all' '--report --list' '--execute --dry-run' '--wat'; do
    # shellcheck disable=SC2086
    run "$REPO_ROOT/scripts/cleanup-storage.sh" $args
    [ "$status" -ne 0 ]
    [ -f "$XDG_CACHE_HOME/selenium/download" ]
  done
}
@test "storage refuses symlinked targets before clearing any cache" {
  rm -rf "$HOME/.yarn/berry/cache"
  ln -s "$HOME/.omlx/models" "$HOME/.yarn/berry/cache"
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --execute --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"Refusing symlinked target"* ]]
  [ -f "$XDG_CACHE_HOME/selenium/download" ]
  [ -f "$HOME/.omlx/models/model" ]
}
@test "storage rejects root and relative cache roots" {
  run env XDG_CACHE_HOME=relative "$REPO_ROOT/scripts/cleanup-storage.sh" --execute --all
  [ "$status" -ne 0 ]
  mkdir -p "$TEST_TMP_DIR/bin"
  printf '#!/usr/bin/env bash\necho 0\n' > "$TEST_TMP_DIR/bin/id"
  chmod +x "$TEST_TMP_DIR/bin/id"
  run env PATH="$TEST_TMP_DIR/bin:$PATH" "$REPO_ROOT/scripts/cleanup-storage.sh" --execute --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"without sudo"* ]]
}

@test "storage interactive chooser previews sizes and cancels without deletion" {
  run bash -c 'printf "1\nno\n" | "$1" --interactive' _ "$REPO_ROOT/scripts/cleanup-storage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enter item numbers"* ]]
  [[ "$output" == *"ALL Factory data"* ]]
  [[ "$output" == *"Permanently delete"* ]]
  [ -f "$XDG_CACHE_HOME/selenium/download" ]
}

@test "storage interactive chooser deletes only confirmed selection" {
  # Fixture's first existing catalog target is Selenium.
  run bash -c 'printf "1\nyes\n" | "$1" --interactive' _ "$REPO_ROOT/scripts/cleanup-storage.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CACHE_HOME/selenium" ]
  [ -f "$XDG_CACHE_HOME/huggingface/model" ]
  [ -f "$HOME/.factory/settings.json" ]
}

@test "storage interactive chooser rejects invalid input and handles EOF" {
  run bash -c 'printf "999\nyes\n" | "$1" --interactive' _ "$REPO_ROOT/scripts/cleanup-storage.sh"
  [ "$status" -ne 0 ]
  [ -f "$XDG_CACHE_HOME/selenium/download" ]
  run bash -c '"$1" --interactive < /dev/null' _ "$REPO_ROOT/scripts/cleanup-storage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cancelled"* ]]
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --interactive --no-input
  [ "$status" -ne 0 ]
}

@test "storage whitespace-only selection cancels without asking for deletion" {
  run bash -c 'printf "   \n" | "$1" --interactive' _ "$REPO_ROOT/scripts/cleanup-storage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cancelled"* ]]
  [[ "$output" != *"Permanently delete"* ]]
  [ -f "$XDG_CACHE_HOME/selenium/download" ]
}

@test "storage refuses symlinked parent directories before removing unrelated data" {
  mkdir -p "$TEST_TMP_DIR/unrelated/cache"
  touch "$TEST_TMP_DIR/unrelated/cache/keep"
  rm -rf "$HOME/.yarn/berry"
  ln -s "$TEST_TMP_DIR/unrelated" "$HOME/.yarn/berry"
  run "$REPO_ROOT/scripts/cleanup-storage.sh" --execute --target yarn
  [ "$status" -ne 0 ]
  [ -f "$TEST_TMP_DIR/unrelated/cache/keep" ]
}
