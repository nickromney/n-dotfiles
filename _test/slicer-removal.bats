#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_TMP_DIR="$(mktemp -d)"
  mkdir -p "$TEST_TMP_DIR/helper/slicer-mac" "$TEST_TMP_DIR/home" "$TEST_TMP_DIR/bin" "$TEST_TMP_DIR/runtime with spaces"
  cp "$REPO_ROOT/slicer-mac/remove-slicer-mac.sh" "$TEST_TMP_DIR/helper/"
  for cmd in pgrep launchctl; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$TEST_TMP_DIR/bin/$cmd"
    chmod +x "$TEST_TMP_DIR/bin/$cmd"
  done
  # Never touch host-wide CLI artifacts during execute tests.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMP_DIR/bin/sudo"
  chmod +x "$TEST_TMP_DIR/bin/sudo"
  export HOME="$TEST_TMP_DIR/home"
  export PATH="$TEST_TMP_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_TMP_DIR"
}

@test "Slicer removal previews sandbox, nested and explicit custom disks without deletion" {
  touch "$TEST_TMP_DIR/helper/sbox-1.img" "$TEST_TMP_DIR/helper/slicer-mac/slicer-base.img"
  touch "$TEST_TMP_DIR/runtime with spaces/custom-1.img"
  run "$TEST_TMP_DIR/helper/remove-slicer-mac.sh" --runtime-dir "$TEST_TMP_DIR/runtime with spaces" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"sbox-1.img"* ]]
  [[ "$output" == *"slicer-base.img"* ]]
  [[ "$output" == *"custom-1.img"* ]]
  [ -f "$TEST_TMP_DIR/runtime with spaces/custom-1.img" ]
  [ -f "$TEST_TMP_DIR/helper/sbox-1.img" ]
}

@test "Slicer removal executes idempotently and preserves configs, shared folders and symlink targets" {
  local runtime="$TEST_TMP_DIR/runtime with spaces"
  mkdir -p "$runtime/oci-cache" "$runtime/shared" "$TEST_TMP_DIR/outside"
  touch "$runtime/custom-1.img" "$runtime/sbox-base.img" "$runtime/slicer-mac.yaml" "$runtime/shared/keep.img" "$TEST_TMP_DIR/outside/keep.img"
  ln -s "$TEST_TMP_DIR/outside/keep.img" "$runtime/linked.img"
  run "$TEST_TMP_DIR/helper/remove-slicer-mac.sh" --runtime-dir "$runtime" --execute --no-input
  [ "$status" -eq 0 ]
  [ ! -e "$runtime/custom-1.img" ]
  [ ! -e "$runtime/sbox-base.img" ]
  [ ! -e "$runtime/oci-cache" ]
  [ ! -L "$runtime/linked.img" ]
  [ -f "$runtime/slicer-mac.yaml" ]
  [ -f "$runtime/shared/keep.img" ]
  [ -f "$TEST_TMP_DIR/outside/keep.img" ]
  run "$TEST_TMP_DIR/helper/remove-slicer-mac.sh" --runtime-dir "$runtime" --execute
  [ "$status" -eq 0 ]
}

@test "Slicer removal rejects missing directories, broad roots and unknown arguments" {
  for arg in --runtime-dir --wat; do
    run "$TEST_TMP_DIR/helper/remove-slicer-mac.sh" "$arg"
    [ "$status" -ne 0 ]
  done
  for dir in / "$HOME" "$TEST_TMP_DIR/missing"; do
    run "$TEST_TMP_DIR/helper/remove-slicer-mac.sh" --runtime-dir "$dir"
    [ "$status" -ne 0 ]
  done
}

@test "Slicer removal rejects sudo before removing files" {
  printf '#!/usr/bin/env bash\necho 0\n' > "$TEST_TMP_DIR/bin/id"
  chmod +x "$TEST_TMP_DIR/bin/id"
  run "$TEST_TMP_DIR/helper/remove-slicer-mac.sh" --execute
  [ "$status" -ne 0 ]
  [[ "$output" == *"do not run this script with sudo"* ]]
}

@test "Slicer removal refuses deletion if daemon survives shutdown" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMP_DIR/bin/pgrep"
  for cmd in pkill sleep; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMP_DIR/bin/$cmd"
    chmod +x "$TEST_TMP_DIR/bin/$cmd"
  done
  touch "$TEST_TMP_DIR/helper/sbox-1.img"
  run "$TEST_TMP_DIR/helper/remove-slicer-mac.sh" --execute
  [ "$status" -ne 0 ]
  [[ "$output" == *"still running"* ]]
  [ -f "$TEST_TMP_DIR/helper/sbox-1.img" ]
}

@test "Slicer removal refuses cleanup when process inspection fails" {
  printf '#!/usr/bin/env bash\nexit 3\n' > "$TEST_TMP_DIR/bin/pgrep"
  touch "$TEST_TMP_DIR/helper/sbox-1.img"
  run "$TEST_TMP_DIR/helper/remove-slicer-mac.sh" --execute
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot inspect Slicer processes"* ]]
  [ -f "$TEST_TMP_DIR/helper/sbox-1.img" ]
}
