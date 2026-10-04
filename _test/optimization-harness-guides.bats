#!/usr/bin/env bats

setup() {
  export PERF_DIR="$BATS_TEST_TMPDIR/workspace"
  export PERF_TEMP="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$PERF_DIR" "$PERF_TEMP"
  export PERF_SCRIPT="$BATS_TEST_DIRNAME/../scripts/audit-harness-guides.sh"
}

@test "harness audit: counts and first-guide ties survive spaces and UTF-8" {
  mkdir -p "$PERF_DIR/space name" "$PERF_DIR/unicode"
  printf 'one two\nthree four\n' > "$PERF_DIR/space name/AGENTS.md"
  printf 'five six\nseven eight\n' > "$PERF_DIR/space name/CLAUDE.md"
  printf 'é\n' > "$PERF_DIR/space name/GEMINI.md"
  printf 'café\n' > "$PERF_DIR/unicode/AGENTS.md"

  run env LC_ALL=C TMPDIR="$PERF_TEMP" /bin/bash "$PERF_SCRIPT" \
    --execute --all --format tsv --root "$PERF_DIR"
  [ "$status" -eq 0 ]
  local counts
  counts="$(printf '%s\n' "$output" | awk -F '\t' '$1=="space name" {print $2 "|" $3 "|" $4 "|" $5 "|" $6}')"
  [ "$counts" = '3|AGENTS.md|2|4|19' ]
  counts="$(printf '%s\n' "$output" | awk -F '\t' '$1=="unicode" {print $2 "|" $3 "|" $4 "|" $5 "|" $6}')"
  [ "$counts" = '1|AGENTS.md|1|1|6' ]
  [ -z "$(find "$PERF_TEMP" -mindepth 1 -print -quit)" ]
}

@test "harness audit: empty and unterminated guides keep their count behavior" {
  mkdir -p "$PERF_DIR/empty" "$PERF_DIR/unterminated"
  : > "$PERF_DIR/empty/AGENTS.md"
  printf 'alpha beta' > "$PERF_DIR/unterminated/AGENTS.md"

  run env LC_ALL=C TMPDIR="$PERF_TEMP" /bin/bash "$PERF_SCRIPT" \
    --execute --all --format tsv --root "$PERF_DIR"
  [ "$status" -eq 0 ]
  local counts
  counts="$(printf '%s\n' "$output" | awk -F '\t' '$1=="empty" {print $2 "|" $3 "|" $4 "|" $5 "|" $6}')"
  [ "$counts" = '1|-|0|0|0' ]
  counts="$(printf '%s\n' "$output" | awk -F '\t' '$1=="unterminated" {print $2 "|" $3 "|" $4 "|" $5 "|" $6}')"
  [ "$counts" = '1|AGENTS.md|0|2|10' ]
}

@test "harness audit: failed counter preserves its exit status and cleans temporary files" {
  mkdir -p "$PERF_DIR/fixture" "$BATS_TEST_TMPDIR/bin"
  printf 'word\n' > "$PERF_DIR/fixture/AGENTS.md"
  cat > "$BATS_TEST_TMPDIR/bin/wc" <<'EOF'
#!/bin/sh
printf '0 0 0\n'
printf 'fixture counter failed\n' >&2
exit 7
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/wc"

  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" TMPDIR="$PERF_TEMP" \
    /bin/bash "$PERF_SCRIPT" --execute --all --format tsv --root "$PERF_DIR"
  [ "$status" -eq 7 ]
  [[ "$output" == *'fixture counter failed'* ]]
  [[ "$output" != *'# summary'* ]]
  [ -z "$(find "$PERF_TEMP" -mindepth 1 -print -quit)" ]
}
