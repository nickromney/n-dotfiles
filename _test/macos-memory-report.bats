#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_TMP_DIR
  TEST_TMP_DIR="$(mktemp -d)"
  mkdir -p "$TEST_TMP_DIR/bin"

  cat >"$TEST_TMP_DIR/bin/mock-uname" <<'EOF'
#!/usr/bin/env bash
echo Darwin
EOF

  cat >"$TEST_TMP_DIR/bin/mock-date" <<'EOF'
#!/usr/bin/env bash
echo 2026-08-25T22:00:00+0100
EOF

  cat >"$TEST_TMP_DIR/bin/mock-sysctl" <<'EOF'
#!/usr/bin/env bash
echo 17179869184
EOF

  cat >"$TEST_TMP_DIR/bin/mock-memory-pressure" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
The system has 17179869184 (1048576 pages with a page size of 16384).
Pages used by compressor: 65536
System-wide memory free percentage: 42%
OUT
EOF

  cat >"$TEST_TMP_DIR/bin/mock-ps" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
  10     1  10240  1.5 01:00 /Applications/AeroSpace.app/Contents/MacOS/AeroSpace
  11    10   1024  0.0 00:59 /bin/bash -c sleep 2 && /opt/homebrew/bin/borders width=8
  12    11  20480  0.5 00:58 /opt/homebrew/bin/borders width=8
  20     1 102400  2.0 00:30 /Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow
  21    20  51200  3.0 00:29 /Applications/Wispr Flow.app/Contents/Frameworks/Wispr Flow Helper.app/Contents/MacOS/Wispr Flow Helper
OUT
printf '  99     1   2048  0.0 00:01 test-parent --group Flow=/Applications/Wispr Flow[.]app/\n'
printf '  98    99   1024  0.0 00:01 test-sampler --group Flow=/Applications/Wispr Flow[.]app/\n'
EOF

  cat >"$TEST_TMP_DIR/bin/mock-footprint" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    10) current=10485760; peak=12582912; name=AeroSpace ;;
    11) current=1048576; peak=1048576; name=bash ;;
    12) current=20971520; peak=31457280; name=borders ;;
    20) current=104857600; peak=125829120; name='Wispr Flow' ;;
    21) current=52428800; peak=62914560; name='Wispr Flow Helper' ;;
    *) continue ;;
  esac
  printf '%s\n' "${name} [${arg}]: 64-bit    Footprint: ${current} B"
  printf '    phys_footprint_peak: %s B\n' "$peak"
done
EOF

  cat >"$TEST_TMP_DIR/bin/mock-sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$MEMORY_REPORT_SLEEP_LOG"
EOF

  chmod +x "$TEST_TMP_DIR/bin/"*
}

teardown() {
  rm -rf "$TEST_TMP_DIR"
}

run_report() {
  run env \
    MEMORY_REPORT_PS_CMD="$TEST_TMP_DIR/bin/mock-ps" \
    MEMORY_REPORT_FOOTPRINT_CMD="$TEST_TMP_DIR/bin/mock-footprint" \
    MEMORY_REPORT_MEMORY_PRESSURE_CMD="$TEST_TMP_DIR/bin/mock-memory-pressure" \
    MEMORY_REPORT_SYSCTL_CMD="$TEST_TMP_DIR/bin/mock-sysctl" \
    MEMORY_REPORT_UNAME_CMD="$TEST_TMP_DIR/bin/mock-uname" \
    MEMORY_REPORT_DATE_CMD="$TEST_TMP_DIR/bin/mock-date" \
    MEMORY_REPORT_SLEEP_CMD="$TEST_TMP_DIR/bin/mock-sleep" \
    MEMORY_REPORT_SLEEP_LOG="$TEST_TMP_DIR/sleep.log" \
    MEMORY_REPORT_SELF_PID=98 \
    "$REPO_ROOT/scripts/macos-memory-report.sh" "$@"
}

@test "macOS memory report groups related processes and prefers footprint" {
  run_report --format tsv

  [ "$status" -eq 0 ]
  [[ "$output" == *$'AeroSpace\t1\t10.0\t10.0\t12.0\t1.5'* ]]
  [[ "$output" == *$'borders\t2\t21.0\t21.0\t31.0\t0.5'* ]]
  [[ "$output" == *$'Wispr Flow\t2\t150.0\t150.0\t180.0\t5.0'* ]]
  [[ "$output" == *'# system_memory_gib=16.0 free_percent=42 compressor_mib=1024.0'* ]]
}

@test "macOS memory report supports custom-only groups" {
  run_report --format tsv --no-default-groups --group 'Flow=/Applications/Wispr Flow[.]app/'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'Flow\t2\t150.0\t150.0\t180.0\t5.0'* ]]
  [[ "$output" != *$'AeroSpace\t'* ]]
}

@test "macOS memory report samples the requested count" {
  run_report --format tsv --count 2 --interval 7

  [ "$status" -eq 0 ]
  [ "$(grep -c $'Wispr Flow\t' <<<"$output")" -eq 2 ]
  run cat "$TEST_TMP_DIR/sleep.log"
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]
}

@test "macOS memory report rejects invalid options" {
  run_report --count 0

  [ "$status" -eq 1 ]
  [[ "$output" == *"--count requires a positive integer"* ]]

  run_report --wat

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --wat"* ]]

  run_report --no-default-groups --group 'broken=['

  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid process-group regex"* ]]
}
