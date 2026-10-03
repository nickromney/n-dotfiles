#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_ROOT="$BATS_TEST_TMPDIR/manifest"
  TEST_REPO="$TEST_ROOT/repo"
  TEST_BIN="$TEST_ROOT/bin"
  mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/mise/.config/mise" "$TEST_BIN"
  cp "$REPO_ROOT/scripts/audit-system-tools.sh" "$REPO_ROOT/scripts/audit-installed.sh" "$TEST_REPO/scripts/"
  printf 'brew "mac-only"\n' >"$TEST_REPO/Brewfile"
  printf 'brew "linux-managed"\n' >"$TEST_REPO/Brewfile.posix"
  printf '[tools]\n' >"$TEST_REPO/mise/.config/mise/config.toml"
  printf '#!/bin/sh\nprintf "Linux\\n"\n' >"$TEST_BIN/uname"
  cat >"$TEST_BIN/brew" <<'EOF'
#!/bin/sh
case "$*" in
  'list --formula'|'leaves') printf 'linux-managed\n' ;;
  'list --cask'|'bundle list --cask'*) : ;;
  'bundle list --formula'*)
    case "$*" in
      *Brewfile.posix*) printf 'linux-managed\n' ;;
      *) printf 'mac-only\n' ;;
    esac
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TEST_BIN/uname" "$TEST_BIN/brew"
  export PATH="$TEST_BIN:/usr/bin:/bin"
}

@test "Linux system audit recognizes tools declared in Brewfile.posix" {
  run env AUDIT_REPO_ROOT="$TEST_REPO" AUDIT_BREW_CMD="$TEST_BIN/brew" AUDIT_MISE_CMD=false \
    "$TEST_REPO/scripts/audit-system-tools.sh" --out-dir "$TEST_ROOT/report" \
    --path "$TEST_BIN" --applications "$TEST_ROOT/no-applications"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_ROOT/report/brew-formulae-declared.txt")" = "linux-managed" ]
  run grep -q 'linux-managed' "$TEST_ROOT/report/brew-leaf-candidates.tsv"
  [ "$status" -eq 1 ]
  run grep -q 'mac-only' "$TEST_ROOT/report/brew-declared-missing.tsv"
  [ "$status" -eq 1 ]
}

@test "installed audit keeps dynamic and tap-qualified casks managed" {
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"$TEST_BIN/uname"
  cat >"$TEST_REPO/Brewfile" <<'EOF'
jetbrains_ide = ENV.fetch("JETBRAINSIDE", "RubyMine").downcase
cask jetbrains_ide
cask "goreleaser/tap/goreleaser"
EOF
  cat >"$TEST_BIN/brew" <<'EOF'
#!/bin/sh
case "$*" in
  'list --cask'|'bundle list --cask'*) printf 'rubymine\ngoreleaser\n' ;;
  *) exit 0 ;;
esac
EOF

  run "$TEST_REPO/scripts/audit-installed.sh" --out-base "$TEST_ROOT/report"

  [ "$status" -eq 0 ]
  local unmanaged_files=("$TEST_ROOT"/report/*/brew-unmanaged.txt)
  run grep -q '^rubymine$\|^goreleaser$' "${unmanaged_files[0]}"
  [ "$status" -eq 1 ]
}

@test "system audit uses evaluated Brewfile declarations" {
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"$TEST_BIN/uname"
  cat >"$TEST_REPO/Brewfile" <<'EOF'
brew "static-managed"
if ENV["INCLUDE_OPTIONAL"] == "true"
  brew "optional-disabled"
end
jetbrains_ide = ENV.fetch("JETBRAINSIDE", "RubyMine").downcase
cask jetbrains_ide
cask "goreleaser/tap/goreleaser"
EOF
  cat >"$TEST_BIN/brew" <<'EOF'
#!/bin/sh
case "$*" in
  'list --formula'|'leaves'|'bundle list --formula'*) printf 'static-managed\n' ;;
  'list --cask'|'bundle list --cask'*) printf 'rubymine\ngoreleaser/tap/goreleaser\n' ;;
  *) exit 0 ;;
esac
EOF

  run env AUDIT_REPO_ROOT="$TEST_REPO" AUDIT_BREW_CMD="$TEST_BIN/brew" AUDIT_MISE_CMD=false \
    "$TEST_REPO/scripts/audit-system-tools.sh" --out-dir "$TEST_ROOT/report" \
    --path "$TEST_BIN" --applications "$TEST_ROOT/no-applications"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_ROOT/report/brew-formulae-declared.txt")" = "static-managed" ]
  run grep -q 'optional-disabled' "$TEST_ROOT/report/brew-declared-missing.tsv"
  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_ROOT/report/brew-casks-declared.txt")" = $'goreleaser\nrubymine' ]
}
