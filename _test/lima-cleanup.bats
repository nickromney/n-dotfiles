#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_TMP_DIR="$(mktemp -d)"
  export LIMA_FIXTURE="$TEST_TMP_DIR/inventory"
  export LIMA_CALLS="$TEST_TMP_DIR/calls"
  export HOME="$TEST_TMP_DIR/home"
  export XDG_CACHE_HOME="$TEST_TMP_DIR/cache"
  mkdir -p "$HOME"
  export LIMA_HOME="$TEST_TMP_DIR/lima"
  mkdir -p "$TEST_TMP_DIR/bin" "$LIMA_HOME/alpha" "$TEST_TMP_DIR/shared"
  printf 'alpha Running\nbeta Stopped\n' > "$LIMA_FIXTURE"
  touch "$LIMA_HOME/alpha/disk" "$TEST_TMP_DIR/shared/keep"
  cat > "$TEST_TMP_DIR/bin/limactl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$LIMA_CALLS"
[[ "$1" == --tty=false ]] || exit 98
shift
case "$1" in
  list)
    [[ "${FAIL_LIST:-0}" == 0 ]] || exit 1
    cat "$LIMA_FIXTURE"
    ;;
  stop) [[ "${FAIL_STOP:-0}" == 0 ]] ;;
  delete)
    [[ "${FAIL_DELETE:-0}" == 0 ]] || exit 1
    shift
    [[ "$1" != --force ]] || shift
    awk -v name="$1" '$1 != name' "$LIMA_FIXTURE" > "$LIMA_FIXTURE.next"
    mv "$LIMA_FIXTURE.next" "$LIMA_FIXTURE"
    rm -rf "$LIMA_HOME/$1"
    ;;
  *) exit 99 ;;
esac
MOCK
  chmod +x "$TEST_TMP_DIR/bin/limactl"
  export PATH="$TEST_TMP_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_TMP_DIR"; }

@test "Lima cleanup help includes examples and deletion scope" {
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Examples:"* ]]
  [[ "$output" == *"even if no instances remain"* ]]
  [[ "$output" == *"~/Library/Caches/lima"* ]]
  [[ "$output" == *"--instance keeps this shared cache"* ]]
  [[ "$output" == *"additional disks are retained"* ]]
  [ ! -e "$LIMA_CALLS" ]
}

@test "Lima cleanup defaults to preview without stopping or deleting" {
  run "$REPO_ROOT/scripts/cleanup-lima.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha (Running)"* ]]
  [[ "$output" == *"beta (Stopped)"* ]]
  [[ "$output" == *"No changes made"* ]]
  [ "$(wc -l < "$LIMA_CALLS" | tr -d ' ')" -eq 1 ]
  [ -f "$LIMA_HOME/alpha/disk" ]
}

@test "Lima cleanup selected execute stops before deleting and preserves shared data" {
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --no-input --instance alpha --instance alpha
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$LIMA_CALLS")" = '--tty=false stop alpha' ]
  [ "$(sed -n '3p' "$LIMA_CALLS")" = '--tty=false delete alpha' ]
  [ "$(wc -l < "$LIMA_CALLS" | tr -d ' ')" -eq 3 ]
  [ ! -e "$LIMA_HOME/alpha" ]
  [ -f "$TEST_TMP_DIR/shared/keep" ]
  [ "$(cat "$LIMA_FIXTURE")" = 'beta Stopped' ]
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --instance alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already absent: alpha"* ]]
}

@test "Lima cleanup all deletes running and stopped instances" {
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -eq 0 ]
  [ ! -s "$LIMA_FIXTURE" ]
  [[ "$(cat "$LIMA_CALLS")" == *'delete beta'* ]]
  [[ "$(cat "$LIMA_CALLS")" != *'stop beta'* ]]
}

@test "Lima cleanup rejects missing selection, invalid names and conflicting flags before inspection" {
  for args in '--execute' '--instance' '--instance ../alpha' '--instance --all' '--wat' '--all --instance alpha' '--execute --dry-run'; do
    # Intentional splitting: each fixture is a sequence of simple CLI words.
    # shellcheck disable=SC2086
    run "$REPO_ROOT/scripts/cleanup-lima.sh" $args
    [ "$status" -ne 0 ]
    [ ! -e "$LIMA_CALLS" ]
  done
}

@test "Lima cleanup handles empty inventory idempotently" {
  : > "$LIMA_FIXTURE"
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to remove"* ]]
}

@test "Lima cleanup fails closed on listing failure or malformed inventory" {
  run env FAIL_LIST=1 "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot list"* ]]
  printf '../unsafe Running\n' > "$LIMA_FIXTURE"
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unexpected Lima inventory"* ]]
  [[ "$(cat "$LIMA_CALLS")" != *'delete'* ]]
}

@test "Lima cleanup refuses broken state before deleting any selected VM" {
  printf 'alpha Running\nbeta Broken\n' > "$LIMA_FIXTURE"
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"explicitly use --force"* ]]
  [ "$(wc -l < "$LIMA_CALLS" | tr -d ' ')" -eq 1 ]
}

@test "Lima cleanup explicit force forwards flags for broken instances" {
  printf 'alpha Broken\n' > "$LIMA_FIXTURE"
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --force --instance alpha
  [ "$status" -eq 0 ]
  [[ "$(cat "$LIMA_CALLS")" == *'stop --force alpha'* ]]
  [[ "$(cat "$LIMA_CALLS")" == *'delete --force alpha'* ]]
}

@test "Lima cleanup never deletes after stop failure" {
  run env FAIL_STOP=1 "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --instance alpha
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to stop"* ]]
  [[ "$(cat "$LIMA_CALLS")" != *'delete'* ]]
  [ -f "$LIMA_HOME/alpha/disk" ]
}

@test "Lima cleanup reports delete failure and leaves remaining VMs untouched" {
  run env FAIL_DELETE=1 "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to delete alpha"* ]]
  [[ "$(cat "$LIMA_CALLS")" != *'delete beta'* ]]
}

@test "Lima cleanup rejects root" {
  printf '#!/usr/bin/env bash\necho 0\n' > "$TEST_TMP_DIR/bin/id"
  chmod +x "$TEST_TMP_DIR/bin/id"
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"without sudo"* ]]
  [ ! -e "$LIMA_CALLS" ]
}


@test "Lima cleanup previews cache and clears it with no instances remaining" {
  local cache
  if [[ "$(uname -s)" == Darwin ]]; then
    cache="$HOME/Library/Caches/lima"
  else
    cache="$XDG_CACHE_HOME/lima"
  fi
  mkdir -p "$cache" "${cache%/lima}/other-app"
  touch "$cache/download" "${cache%/lima}/other-app/keep"
  : > "$LIMA_FIXTURE"
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --dry-run --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would clear Lima cache: $cache"* ]]
  [ -f "$cache/download" ]
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -eq 0 ]
  [ ! -e "$cache" ]
  [ -f "${cache%/lima}/other-app/keep" ]
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -eq 0 ]
}

@test "Lima cleanup preserves cache for selected-instance deletion and on deletion failure" {
  local cache
  if [[ "$(uname -s)" == Darwin ]]; then
    cache="$HOME/Library/Caches/lima"
  else
    cache="$XDG_CACHE_HOME/lima"
  fi
  mkdir -p "$cache"
  touch "$cache/download"
  run env FAIL_DELETE=1 "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --all
  [ "$status" -ne 0 ]
  [ -f "$cache/download" ]
  run "$REPO_ROOT/scripts/cleanup-lima.sh" --execute --instance alpha
  [ "$status" -eq 0 ]
  [ -f "$cache/download" ]
}
