#!/usr/bin/env bats

setup() {
  export PERF_SYSTEM_SCRIPT="${PERF_SYSTEM_SCRIPT:-$BATS_TEST_DIRNAME/../scripts/audit-system-tools.sh}"
  export PERF_DATA="$BATS_TEST_TMPDIR/data"
  mkdir -p "$PERF_DATA" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/apps" \
    "$BATS_TEST_TMPDIR/path" "$BATS_TEST_TMPDIR/repo/mise/.config/mise"
  printf '# fixture\n' > "$BATS_TEST_TMPDIR/repo/Brewfile"
  printf '# fixture\n' > "$BATS_TEST_TMPDIR/repo/Brewfile.posix"
  printf '[tools]\n' > "$BATS_TEST_TMPDIR/repo/mise/.config/mise/config.toml"
  cat > "$BATS_TEST_TMPDIR/bin/brew" <<'MOCK'
#!/bin/sh
case "$*" in
  'list --formula') name=formula;;
  'list --cask') name=cask;;
  leaves) name=leaves;;
  'bundle list --formula'*) name=declared-formula;;
  'bundle list --cask'*) name=declared-cask;;
  *) exit 1;;
esac
cat "$PERF_DATA/$name"
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  for name in formula cask leaves declared-formula declared-cask; do
    : > "$PERF_DATA/$name"
  done
}

run_audit() {
  run env LC_ALL=C AUDIT_REPO_ROOT="$BATS_TEST_TMPDIR/repo" \
    AUDIT_OUT_DIR="$BATS_TEST_TMPDIR/report" AUDIT_PATH="$BATS_TEST_TMPDIR/path" \
    AUDIT_APPLICATION_ROOTS="$BATS_TEST_TMPDIR/apps" \
    AUDIT_BREW_CMD="$BATS_TEST_TMPDIR/bin/brew" AUDIT_MISE_CMD=nonexistent-fixture-mise \
    /bin/bash "$PERF_SYSTEM_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "system audit: empty lookup inventories preserve all missing and unmanaged rows" {
  printf 'zeta\nalpha\n' > "$PERF_DATA/leaves"
  printf 'app-z\napp-a\n' > "$PERF_DATA/cask"
  run_audit
  [ "$(cut -f2 "$BATS_TEST_TMPDIR/report/brew-leaf-candidates.tsv" | tail -n +2)" = $'alpha\nzeta' ]
  [ "$(cut -f2 "$BATS_TEST_TMPDIR/report/brew-cask-candidates.tsv" | tail -n +2)" = $'app-a\napp-z' ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/report/brew-declared-missing.tsv" | tr -d ' ')" = 1 ]
}

@test "system audit: membership is literal and missing formula rows precede cask rows" {
  printf '1\na.b\naXb\n' > "$PERF_DATA/formula"
  cp "$PERF_DATA/formula" "$PERF_DATA/leaves"
  printf '01\na.b\n' > "$PERF_DATA/declared-formula"
  printf 'installed-app\n' > "$PERF_DATA/cask"
  printf 'missing-app\n' > "$PERF_DATA/declared-cask"
  run_audit
  [ "$(cut -f2 "$BATS_TEST_TMPDIR/report/brew-leaf-candidates.tsv" | tail -n +2)" = $'1\naXb' ]
  [ "$(cut -f1,2 "$BATS_TEST_TMPDIR/report/brew-declared-missing.tsv" | tail -n +2)" = $'formula\t01\ncask\tmissing-app' ]
}

@test "system audit: overlap preserves sorted literal names and empty mise maps" {
  printf '1\n01\naXb\na.b\n' > "$PERF_DATA/formula"
  printf '[tools]\n"01" = "latest"\n"a.b" = "latest"\n' > "$BATS_TEST_TMPDIR/repo/mise/.config/mise/config.toml"
  run_audit
  [ "$(cut -f1,2 "$BATS_TEST_TMPDIR/report/brew-mise-overlap.tsv" | tail -n +2)" = $'01\t01\na.b\ta.b' ]
  printf '[tools]\n' > "$BATS_TEST_TMPDIR/repo/mise/.config/mise/config.toml"
  run_audit
  [ "$(wc -l < "$BATS_TEST_TMPDIR/report/brew-mise-overlap.tsv" | tr -d ' ')" = 1 ]
}
