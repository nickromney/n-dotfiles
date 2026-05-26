#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_TMP_DIR
  TEST_TMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP_DIR"
}

assert_help_contract() {
  local script="$1"

  run "$REPO_ROOT/$script" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Examples:"* ]]
}

@test "user-facing scripts expose help with examples" {
  local script
  scripts=(
    "bootstrap.sh"
    "install.sh"
    "setup-personal-mac.sh"
    "setup-work-mac.sh"
    "setup-ssh-from-1password.sh"
    "setup-gitconfig-from-1password.sh"
    "_macos/macos.sh"
    "scripts/generate-brewfile.sh"
    "scripts/generate-install-manifests.sh"
    "scripts/audit.sh"
    "scripts/audit-harness-guides.sh"
    "scripts/audit-installed.sh"
    "scripts/sync-private-harness-assets.sh"
    "scripts/build-browser-tools.sh"
    "slicer-mac/check-slicer-version.sh"
    "slicer-mac/install-slicer-mac.sh"
    "slicer-mac/remove-slicer-mac.sh"
    "slicer-mac/restart-slicer-mac.sh"
  )

  for script in "${scripts[@]}"; do
    assert_help_contract "$script"
  done
}

@test "generate-brewfile: dry-run previews output without writing the file" {
  if ! command -v yq >/dev/null 2>&1; then
    skip "yq is required for manifest generation tests"
  fi

  cat >"$TEST_TMP_DIR/core.yaml" <<'EOF'
tools:
  jq:
    manager: brew
    type: package
  ghostty:
    manager: brew
    type: cask
EOF

  run "$REPO_ROOT/scripts/generate-brewfile.sh" --dry-run --output-file "$TEST_TMP_DIR/Brewfile" --config "$TEST_TMP_DIR/core.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would write $TEST_TMP_DIR/Brewfile"* ]]
  [[ "$output" == *'brew "jq"'* ]]
  [[ "$output" == *'cask "ghostty"'* ]]
  [ ! -f "$TEST_TMP_DIR/Brewfile" ]
}

@test "generate-install-manifests: dry-run previews all manifest files without writing them" {
  if ! command -v yq >/dev/null 2>&1; then
    skip "yq is required for manifest generation tests"
  fi

  cat >"$TEST_TMP_DIR/core.yaml" <<'EOF'
tools:
  kubectl:
    manager: arkade
    type: get
    install_args: ["--path", "/tmp/tools"]
  jq:
    manager: brew
    type: package
EOF

  run "$REPO_ROOT/scripts/generate-install-manifests.sh" --dry-run --output-dir "$TEST_TMP_DIR/out" --config "$TEST_TMP_DIR/core.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would generate install manifests in $TEST_TMP_DIR/out"* ]]
  [[ "$output" == *"--- $TEST_TMP_DIR/out/Brewfile ---"* ]]
  [[ "$output" == *"--- $TEST_TMP_DIR/out/arkade.tsv ---"* ]]
  [[ "$output" == *"--- $TEST_TMP_DIR/out/metadata.json ---"* ]]
  [ ! -d "$TEST_TMP_DIR/out" ]
}

@test "build-browser-tools: dry-run prints the planned build commands" {
  run "$REPO_ROOT/scripts/build-browser-tools.sh" --dry-run --bin-dir "$TEST_TMP_DIR/bin"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would"* ]]
  [[ "$output" == *"$TEST_TMP_DIR/bin/browser-tools"* ]]
}
