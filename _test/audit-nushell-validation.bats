#!/usr/bin/env bats

@test "Nushell syntax validation fails for an invalid config" {
  command -v nu >/dev/null 2>&1 || skip "Nushell is required"
  local fixture="$BATS_TEST_TMPDIR/repo"
  local config_dir="$fixture/nushell/Library/Application Support/nushell"
  mkdir -p "$fixture/_test/helpers" "$config_dir"
  cp "$BATS_TEST_DIRNAME/nushell.bats" "$fixture/_test/"
  cp "$BATS_TEST_DIRNAME/helpers/mocks.bash" "$fixture/_test/helpers/"
  printf '%s\n' 'let =' > "$config_dir/config.nu"
  printf '%s\n' '# isolated environment' > "$config_dir/env.nu"

  run bats "$fixture/_test/nushell.bats" --filter 'config.nu syntax is valid'

  [ "$status" -ne 0 ]
  [[ "$output" == *'not ok'* ]]
}
