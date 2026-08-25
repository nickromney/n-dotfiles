#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_TMP_DIR
  TEST_TMP_DIR="$(mktemp -d)"
  mkdir -p "$TEST_TMP_DIR/bin" "$TEST_TMP_DIR/path-one" "$TEST_TMP_DIR/path-two" "$TEST_TMP_DIR/Applications"
}

teardown() {
  rm -rf "$TEST_TMP_DIR"
}

write_mock_brew() {
  cat >"$TEST_TMP_DIR/bin/brew" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "list --formula") printf '%s\n' fd git old-tool ;;
  "list --cask") printf '%s\n' brave-browser old-app ;;
  "leaves") printf '%s\n' fd old-tool ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$TEST_TMP_DIR/bin/brew"
}

write_mock_mise() {
  cat >"$TEST_TMP_DIR/bin/mise" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'node v22.0.0' 'ripgrep latest'
EOF
  chmod +x "$TEST_TMP_DIR/bin/mise"
}

@test "audit-system-tools exposes a report-only CLI contract" {
  run "$REPO_ROOT/scripts/audit-system-tools.sh" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"does not uninstall"* ]]
  [[ "$output" == *"Examples:"* ]]
}

@test "audit-system-tools reports unmanaged leaves, casks, missing paths, and overlaps" {
  write_mock_brew
  write_mock_mise
  printf '#!/usr/bin/env bash\n' >"$TEST_TMP_DIR/path-one/duplicate-tool"
  printf '#!/usr/bin/env bash\n' >"$TEST_TMP_DIR/path-two/duplicate-tool"
  chmod +x "$TEST_TMP_DIR/path-one/duplicate-tool" "$TEST_TMP_DIR/path-two/duplicate-tool"
  mkdir -p "$TEST_TMP_DIR/Applications/Example.app"

  run env \
    PATH="$TEST_TMP_DIR/path-one:$TEST_TMP_DIR/path-two:/usr/bin:/bin" \
    AUDIT_BREW_CMD="$TEST_TMP_DIR/bin/brew" \
    AUDIT_MISE_CMD="$TEST_TMP_DIR/bin/mise" \
    AUDIT_APPLICATION_ROOTS="$TEST_TMP_DIR/Applications" \
    AUDIT_OUT_DIR="$TEST_TMP_DIR/report" \
    "$REPO_ROOT/scripts/audit-system-tools.sh"

  [ "$status" -eq 0 ]
  [[ -f "$TEST_TMP_DIR/report/summary.md" ]]
  grep -q $'formula\told-tool' "$TEST_TMP_DIR/report/brew-leaf-candidates.tsv"
  grep -q $'cask\told-app' "$TEST_TMP_DIR/report/brew-cask-candidates.tsv"
  grep -q $'2\t' "$TEST_TMP_DIR/report/path-directories.tsv"
  grep -q $'duplicate-tool\t2\t' "$TEST_TMP_DIR/report/path-shadowing.tsv"
  grep -q $'Example.app' "$TEST_TMP_DIR/report/applications.tsv"
  grep -q $'fd\tfd\t' "$TEST_TMP_DIR/report/brew-mise-overlap.tsv"
}

@test "audit-system-tools expands the selected JetBrains cask" {
  write_mock_brew
  run env \
    JETBRAINSIDE=WebStorm \
    AUDIT_BREW_CMD="$TEST_TMP_DIR/bin/brew" \
    AUDIT_MISE_CMD="$TEST_TMP_DIR/bin/missing-mise" \
    AUDIT_OUT_DIR="$TEST_TMP_DIR/report" \
    "$REPO_ROOT/scripts/audit-system-tools.sh"

  [ "$status" -eq 0 ]
  grep -q '^webstorm$' "$TEST_TMP_DIR/report/brew-casks-declared.txt"
}
