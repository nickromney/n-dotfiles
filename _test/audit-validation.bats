#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REAL_SHELLCHECK="$(command -v shellcheck || true)"
  REAL_BATS="$(command -v bats)"
  VALIDATION_ORIGINAL_PATH="$PATH"
  TEST_ROOT="$BATS_TEST_TMPDIR/validation"
  TEST_BIN="$TEST_ROOT/bin"
  mkdir -p "$TEST_BIN"
  cp "$REPO_ROOT/Makefile" "$TEST_ROOT/Makefile"
  export PATH="$TEST_BIN:/usr/bin:/bin"
  cd "$TEST_ROOT" || return 1
}

@test "mise install and pin upgrades fail when the package manager fails" {
  cat >"$TEST_BIN/mise" <<'EOF'
#!/bin/sh
echo 'simulated package manager failure' >&2
exit 42
EOF
  chmod +x "$TEST_BIN/mise"

  for target in mise-install mise-bump; do
    run make "$target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"simulated package manager failure"* ]]
    [[ "$output" != *"✓ mise"* ]]
  done
}

@test "make update fails when a Mac App Store upgrade fails" {
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/mise"
  printf '#!/bin/sh\necho "simulated store failure" >&2\nexit 42\n' >"$TEST_BIN/mas"
  chmod +x "$TEST_BIN/mise" "$TEST_BIN/mas"

  run make HOST_OS=Darwin BREW_UPDATE=true update

  [ "$status" -ne 0 ]
  [[ "$output" == *"simulated store failure"* ]]
  [[ "$output" != *"✓ Mac App Store apps updated"* ]]
}

@test "make update fails when a Rust toolchain update fails" {
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/mise"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/mas"
  printf '#!/bin/sh\necho "simulated Rust failure" >&2\nexit 42\n' >"$TEST_BIN/rustup"
  chmod +x "$TEST_BIN/mise" "$TEST_BIN/mas" "$TEST_BIN/rustup"

  run make HOST_OS=Darwin BREW_UPDATE=true update

  [ "$status" -ne 0 ]
  [[ "$output" == *"simulated Rust failure"* ]]
  [[ "$output" != *"✓ Rust updated"* ]]
}

@test "shellcheck gate fails on scanner failures without severity words" {
  mkdir -p "$TEST_ROOT/_test" "$TEST_ROOT/_macos"
  cp "$REPO_ROOT/_test/shellcheck.sh" "$TEST_ROOT/_test/"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_ROOT/_macos/macos.sh"
  cat >"$TEST_BIN/shellcheck" <<'EOF'
#!/bin/sh
echo 'Could not read source file'
exit 2
EOF
  # Do not allow the existing runner to write its shared host /tmp log while
  # demonstrating its exit-status bug. Scanner output still reaches stdout.
  printf '#!/bin/sh\ncat\n' >"$TEST_BIN/tee"
  chmod +x "$TEST_BIN/shellcheck" "$TEST_BIN/tee"

  run "$TEST_ROOT/_test/shellcheck.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not read source file"* ]]
  [[ "$output" != *"All files passed shellcheck"* ]]
}

@test "shellcheck gate follows repository-local shell libraries" {
  [[ -n "$REAL_SHELLCHECK" ]] || skip "shellcheck is not installed"
  mkdir -p "$TEST_ROOT/_test" "$TEST_ROOT/_macos"
  cp "$REPO_ROOT/_test/shellcheck.sh" "$TEST_ROOT/_test/"
  ln -s "$REAL_SHELLCHECK" "$TEST_BIN/shellcheck"
  cat >"$TEST_ROOT/_macos/macos.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck source=_macos/library.bash
source _macos/library.bash
repo_greeting
EOF
  printf 'repo_greeting() { printf "hello\\n"; }\n' >"$TEST_ROOT/_macos/library.bash"

  run "$TEST_ROOT/_test/shellcheck.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"All files passed shellcheck"* ]]
}

@test "Omarchy tests do not call host credential tools" {
  cat >"$TEST_BIN/op" <<EOF
#!/bin/sh
touch "$TEST_ROOT/host-op-called"
exit 1
EOF
  cat >"$TEST_BIN/ssh-add" <<EOF
#!/bin/sh
touch "$TEST_ROOT/host-ssh-add-called"
exit 1
EOF
  chmod +x "$TEST_BIN/op" "$TEST_BIN/ssh-add"

  run env PATH="$TEST_BIN:$VALIDATION_ORIGINAL_PATH" SSH_AUTH_SOCK="$TEST_ROOT/host-agent.sock" \
    "$REAL_BATS" "$REPO_ROOT/_test/bootstrap-omarchy.bats" --filter "warns when a stowed package"

  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output" >&3
  fi
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_ROOT/host-op-called" ]
  [ ! -e "$TEST_ROOT/host-ssh-add-called" ]
}

@test "harness guide audit counts skill files without treating prose as a reference" {
  local workspace="$TEST_ROOT/workspaces/example"
  mkdir -p "$workspace/skills/one"
  printf '# One\n' >"$workspace/skills/one/SKILL.md"
  cat >"$workspace/AGENTS.md" <<'EOF'
Move repeatable procedures to scoped skills/docs.
Use skills/one/SKILL.md.
EOF

  run env PATH="$VALIDATION_ORIGINAL_PATH" "$REPO_ROOT/scripts/audit-harness-guides.sh" \
    --execute --all --format tsv --root "$TEST_ROOT/workspaces"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\t1\t1\t0\tok\tAGENTS.md\t'* ]]
}

@test "macOS memory report accepts default groups in the system Bash" {
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"$TEST_BIN/mock-uname"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/mock-ps"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/mock-footprint"
  chmod +x "$TEST_BIN/mock-uname" "$TEST_BIN/mock-ps" "$TEST_BIN/mock-footprint"

  run env MEMORY_REPORT_UNAME_CMD="$TEST_BIN/mock-uname" MEMORY_REPORT_PS_CMD="$TEST_BIN/mock-ps" \
    MEMORY_REPORT_FOOTPRINT_CMD="$TEST_BIN/mock-footprint" MEMORY_REPORT_SYSCTL_CMD=false \
    MEMORY_REPORT_MEMORY_PRESSURE_CMD=false /bin/bash "$REPO_ROOT/scripts/macos-memory-report.sh" --format tsv

  [ "$status" -eq 0 ]
  [[ "$output" == *$'AeroSpace\t0\t0.0\t0.0\t0.0\t0.0'* ]]
}

@test "harness guide audit supports guided and unguided directories in the system Bash" {
  mkdir -p "$TEST_ROOT/workspaces/guided" "$TEST_ROOT/workspaces/unguided"
  printf '# Guide\n' >"$TEST_ROOT/workspaces/guided/AGENTS.md"

  run env PATH="$VALIDATION_ORIGINAL_PATH" /bin/bash "$REPO_ROOT/scripts/audit-harness-guides.sh" \
    --execute --all --format tsv --root "$TEST_ROOT/workspaces"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'unguided\t0\t-\t0\t0\t0\t0\t0\t0\tno-guide\t-\t'* ]]
  [[ "$output" == *$'\t0\t0\t0\tok\tAGENTS.md\t'* ]]
}

@test "staged shell hook accepts no matching files in the system Bash" {
  run env N_DOTFILES_SKIP_HOOKS=0 /bin/bash "$REPO_ROOT/scripts/hooks/check-staged-shell.sh" --execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"shellcheck: no staged shell files"* ]]
}

@test "staged YAML hook accepts no matching files in the system Bash" {
  run env N_DOTFILES_SKIP_HOOKS=0 /bin/bash "$REPO_ROOT/scripts/hooks/check-staged-yaml.sh" --execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"yamllint: no staged YAML files"* ]]
}

@test "GitHub audit accepts empty optional exclusions in the system Bash" {
  mkdir -p "$TEST_ROOT/clones"
  printf '#!/bin/sh\nprintf "[]\\n"\n' >"$TEST_BIN/gh"
  chmod +x "$TEST_BIN/gh"

  run env PATH="$TEST_BIN:$VALIDATION_ORIGINAL_PATH" /bin/bash "$REPO_ROOT/scripts/audit-github-repos.sh" \
    --execute --no-fetch --root "$TEST_ROOT/clones" --cache-file "$TEST_ROOT/github-cache.json" --format tsv

  [ "$status" -eq 0 ]
  [[ "$output" == *$'github_repos\t0'* ]]
  [[ "$output" == *$'excluded_repos\t0'* ]]
  [[ "$output" == *$'local_repos_scanned\t0'* ]]
}

@test "Stow cleans up an owned legacy agent without old symlinks in the system Bash" {
  local fixture_repo="$TEST_ROOT/repo"
  local fixture_home="$TEST_ROOT/home"
  local plist="$fixture_home/Library/LaunchAgents/com.nickromney.n-borders.plist"
  local daemon="$fixture_home/.local/bin/n-borders-daemon"
  mkdir -p "$fixture_repo/macos-borders" "$fixture_home/Library/LaunchAgents" "$fixture_home/.local/bin"
  cp "$REPO_ROOT/stow.sh" "$fixture_repo/stow.sh"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/stow"
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"$TEST_BIN/uname"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/mock-launchctl"
  chmod +x "$TEST_BIN/stow" "$TEST_BIN/uname" "$TEST_BIN/mock-launchctl"
  printf 'owned daemon\n' >"$daemon"
  cat >"$plist" <<EOF
<key>Label</key><string>com.nickromney.n-borders</string>
<string>$daemon</string>
EOF

  run env HOME="$fixture_home" STOW_LAUNCHCTL_CMD="$TEST_BIN/mock-launchctl" \
    /bin/bash "$fixture_repo/stow.sh" macos-borders

  [ "$status" -eq 0 ]
  [ ! -e "$plist" ]
  [ ! -e "$daemon" ]
  [[ "$output" == *"Removing legacy n-borders integration"* ]]
}
