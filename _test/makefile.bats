#!/usr/bin/env bats

# Tests for Makefile functionality

setup() {
  # Save current directory
  export ORIGINAL_DIR="$PWD"
  local repo_root
  repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT="$repo_root"
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  # Create a minimal test environment
  cd "$TEST_DIR" || return 1
  mkdir -p "$TEST_DIR/mocks"
  export PATH="$TEST_DIR/mocks:$PATH"

  # The Brewfile the Makefile selects depends on the host OS
  if [[ "$(uname -s)" == "Darwin" ]]; then
    export EXPECTED_BREWFILE="Brewfile"
  else
    export EXPECTED_BREWFILE="Brewfile.posix"
  fi

  cat > "$TEST_DIR/mocks/brew" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "bundle" ]]; then
  shift
  printf "%s\n" "$@" > "${TEST_DIR}/brew-bundle-args.txt"
  printf "%s\t%s\n" "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" "${HOMEBREW_NO_ENV_HINTS:-}" > "${TEST_DIR}/brew-policy-env.txt"
  echo "brew bundle called"
  exit 0
fi
echo "brew $*"
exit 0
EOF
  chmod +x "$TEST_DIR/mocks/brew"

  cat > "$TEST_DIR/mocks/mise" <<'EOF'
#!/usr/bin/env bash
echo "mise $*"
exit 0
EOF
  chmod +x "$TEST_DIR/mocks/mise"

  touch Brewfile Brewfile.posix

  cat > stow.sh <<'EOF'
#!/usr/bin/env bash
echo "stow.sh called with: $*"
EOF
  chmod +x stow.sh

  mkdir -p _macos
  cat > _macos/macos.sh <<'EOF'
#!/usr/bin/env bash
echo "macos.sh called with: $@"
EOF
  chmod +x _macos/macos.sh
  touch _macos/personal.yaml _macos/work.yaml

  mkdir -p scripts
  for script in brew-with-policy.sh brew-update.sh; do
    if [ -f "$REPO_ROOT/scripts/$script" ]; then
      cp "$REPO_ROOT/scripts/$script" scripts/
      chmod +x "scripts/$script"
    fi
  done

  # Copy the Makefile
  cp "$REPO_ROOT/Makefile" .
}

teardown() {
  cd "$ORIGINAL_DIR" || return 1
  rm -rf "$TEST_DIR"
}

@test "make help displays usage information" {
  run make help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "n-dotfiles" ]]
  [[ "$output" =~ "Dotfile and Tool Management" ]]
  [[ "$output" =~ "Install" ]]
  [[ "$output" =~ "Update" ]]
  [[ "$output" == *"Typical flows"* ]]
  [[ "$output" == *"make stow"* ]]
}

@test "make default target shows help" {
  run make
  [ "$status" -eq 0 ]
  [[ "$output" =~ "n-dotfiles" ]]
  [[ "$output" =~ "Dotfile and Tool Management" ]]
}

@test "make install runs brew bundle, stow, and mise install" {
  run make install
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew bundle called"* ]]
  [[ "$output" == *"stow.sh called with:"* ]]
  [[ "$output" == *"mise install"* ]]
}

@test "make brewfile-install selects the OS-appropriate Brewfile" {
  run make brewfile-install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "brew bundle called" ]]
  run grep -qx -- "--file=$EXPECTED_BREWFILE" "$TEST_DIR/brew-bundle-args.txt"
  [ "$status" -eq 0 ]
}

@test "make brewfile-install applies Homebrew tap trust policy to brew bundle" {
  run make brewfile-install
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "1" && $2 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
}

@test "make stow calls stow.sh" {
  run make stow
  [ "$status" -eq 0 ]
  [[ "$output" == *"stow.sh called with:"* ]]
}

@test "make mise-install runs mise install" {
  run make mise-install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "mise install" ]]
}

@test "make update uses the shared Homebrew update module and mise upgrade" {
  cat > scripts/brew-update.sh <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "$1" >> "$TEST_DIR/brew-update-calls.txt"
echo "shared Homebrew update module: $1"
exit 0
EOF
  chmod +x scripts/brew-update.sh

  for command in rustup mas; do
    cat > "$TEST_DIR/mocks/$command" <<'EOF'
#!/usr/bin/env bash
echo "$0 $*"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/$command"
  done

  run make update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "shared Homebrew update module: update-all" ]]
  [[ "$output" =~ "mise upgrade" ]]

  run grep -qx "update-all" "$TEST_DIR/brew-update-calls.txt"
  [ "$status" -eq 0 ]
}

@test "make configure defaults to personal macOS profile" {
  run make configure
  [ "$status" -eq 0 ]
  [[ "$output" == *"Applying macOS settings from _macos/personal.yaml"* ]]
  [[ "$output" == *"macos.sh called with: personal.yaml"* ]]
}

@test "make configure MACOS_PROFILE=work calls macos.sh with work yaml" {
  run make configure MACOS_PROFILE=work
  [ "$status" -eq 0 ]
  [[ "$output" == *"Applying macOS settings from _macos/work.yaml"* ]]
  [[ "$output" == *"macos.sh called with: work.yaml"* ]]
}

@test "make with invalid target fails" {
  run make invalid_target
  [ "$status" -ne 0 ]
}
