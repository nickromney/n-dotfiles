#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/locale" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' C POSIX
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/locale"
}

@test "Bash preserves a working locale when British English is unavailable" {
  # shellcheck disable=SC2016 # The child shell expands its own positional argument and locale.
  run env HOME="$HOME" LANG=C PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" \
    bash -c 'OSTYPE=linux-gnu; source "$1" 2>/dev/null; printf "%s\n" "$LANG"' \
    bash "$REPO_ROOT/bash/.bashrc"

  [ "$status" -eq 0 ]
  [ "$output" = C ]
}
