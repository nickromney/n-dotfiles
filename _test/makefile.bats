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

  # Create mock install.sh that just prints its arguments
  cat > install.sh << 'EOF'
#!/usr/bin/env bash
echo "CONFIG_FILES: $CONFIG_FILES"
echo "Arguments: $@"
EOF
  chmod +x install.sh

  cat > "$TEST_DIR/mocks/brew" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "bundle" ]]; then
  shift
  printf "%s\n" "$@" > "${TEST_DIR}/brew-bundle-args.txt"
  if printf "%s\n" "$@" | grep -qx -- "--no-lock"; then
    echo "invalid option: --no-lock" >&2
    exit 1
  fi
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

  touch Brewfile Brewfile.work Brewfile.common Brewfile.all Brewfile.posix
  touch mise.toml

  mkdir -p _macos
  cat > _macos/macos.sh <<'EOF'
#!/usr/bin/env bash
echo "macos.sh called with: $@"
EOF
  chmod +x _macos/macos.sh
  touch _macos/personal.yaml _macos/work.yaml

  mkdir -p scripts
  cat > scripts/generate-install-manifests.sh <<'EOF'
#!/usr/bin/env bash
out_dir="$1"
shift
mkdir -p "$out_dir"
echo "generated manifests for: $*" > "$out_dir/result.txt"
echo "generate-install-manifests called for $out_dir with: $*"
EOF
  chmod +x scripts/generate-install-manifests.sh

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
  [[ "$output" =~ "Main Configurations" ]]
  [[ "$output" =~ "common" ]]
  [[ "$output" =~ "personal" ]]
  [[ "$output" =~ "work" ]]
  [[ "$output" =~ "Focus Configurations" ]]
  [[ "$output" =~ "Actions" ]]
  [[ "$output" =~ "Examples" ]]
}

@test "make install defaults to common profile" {
  run make install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/common" ]]
  [[ ! "$output" =~ "focus/ai" ]]
  [[ ! "$output" =~ "host/personal" ]]
  [[ ! "$output" =~ "host/work" ]]
  [[ "$output" =~ "mise install" ]]
  [[ ! "$output" =~ "brew bundle called" ]]
  [[ ! "$output" =~ "-u" ]]
  [[ ! "$output" =~ "-s" ]]
}

@test "make install-dry-run uses mise dry-run" {
  run make install-dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "mise install --dry-run" ]]
}

@test "make brewfile-install uses supported brew bundle flags" {
  run make brewfile-install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "brew bundle called" ]]
  run grep -qx -- '--file=Brewfile.common' "$TEST_DIR/brew-bundle-args.txt"
  [ "$status" -eq 0 ]
}

@test "make personal without action triggers install" {
  run make personal
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "focus/kubernetes" ]]
}

@test "make install work uses work profile" {
  run make install work
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/work" ]]
  [[ ! "$output" =~ "host/personal" ]]
}

@test "make install all uses all profile bundles" {
  run make install all
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/common" ]]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "host/work" ]]
  [[ "$output" =~ "focus/hardware-home" ]]
  [[ ! "$output" =~ "focus/ai" ]]
}

@test "make work install uses work profile" {
  run make work install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/work" ]]
}

@test "make work stow adds stow flag" {
  run make work stow
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/work" ]]
  [[ "$output" =~ "-s" ]]
}

@test "make personal update adds update flag" {
  run make personal update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "-u" ]]
}

@test "make update defaults to personal profile" {
  run make update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/common" ]]
  [[ "$output" =~ "host/personal" ]]
  [[ "$output" =~ "focus/cloud" ]]
  [[ "$output" =~ "-u" ]]
}

@test "make brew update applies Homebrew tap trust policy to brew commands" {
  cat > "$TEST_DIR/mocks/brew" <<'EOF'
#!/usr/bin/env bash
printf "%s\t%s\t%s\n" "$*" "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" "${HOMEBREW_NO_ENV_HINTS:-}" >> "$TEST_DIR/brew-policy-env.txt"
echo "brew $*"
exit 0
EOF
  chmod +x "$TEST_DIR/mocks/brew"

  run make brew update
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "update" && $2 == "1" && $3 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "upgrade" && $2 == "1" && $3 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "upgrade --cask" && $2 == "1" && $3 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
}

@test "make update-all applies Homebrew tap trust policy to brew commands" {
  cat > "$TEST_DIR/mocks/brew" <<'EOF'
#!/usr/bin/env bash
printf "%s\t%s\t%s\n" "$*" "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" "${HOMEBREW_NO_ENV_HINTS:-}" >> "$TEST_DIR/brew-policy-env.txt"
echo "brew $*"
exit 0
EOF
  chmod +x "$TEST_DIR/mocks/brew"

  for command in rustup uv mas mise; do
    cat > "$TEST_DIR/mocks/$command" <<'EOF'
#!/usr/bin/env bash
echo "$0 $*"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/$command"
  done

  run make update-all
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "update" && $2 == "1" && $3 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "upgrade" && $2 == "1" && $3 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "cleanup" && $2 == "1" && $3 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
}

@test "make Homebrew update targets use the shared Homebrew update module" {
  cat > scripts/brew-update.sh <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "$1" >> "$TEST_DIR/brew-update-calls.txt"
echo "shared Homebrew update module: $1"
exit 0
EOF
  chmod +x scripts/brew-update.sh

  for command in rustup uv mas mise; do
    cat > "$TEST_DIR/mocks/$command" <<'EOF'
#!/usr/bin/env bash
echo "$0 $*"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/$command"
  done

  run make brew update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "shared Homebrew update module: package-manager" ]]

  run make update-all
  [ "$status" -eq 0 ]
  [[ "$output" =~ "shared Homebrew update module: update-all" ]]

  run grep -qx "package-manager" "$TEST_DIR/brew-update-calls.txt"
  [ "$status" -eq 0 ]
  run grep -qx "update-all" "$TEST_DIR/brew-update-calls.txt"
  [ "$status" -eq 0 ]
}

@test "make update passes dry-run flag when requested" {
  DRY_RUN=true run make update
  [ "$status" -eq 0 ]
  [[ "$output" =~ "-u" ]]
  [[ "$output" =~ "-d" ]]
}

@test "PROFILE environment variable overrides selection" {
  PROFILE=work run make install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "host/work" ]]
}

@test "make configure work calls macos.sh with work yaml" {
  run make configure work
  [ "$status" -eq 0 ]
  [[ "$output" == *"Applying macOS settings from _macos/work.yaml"* ]]
  [[ "$output" == *"macos.sh called with: work.yaml"* ]]
}

@test "make vscode runs with correct configs" {
  run make vscode install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "CONFIG_FILES: focus/vscode" ]]
}

@test "make default target shows help" {
  run make
  [ "$status" -eq 0 ]
  [[ "$output" =~ "n-dotfiles" ]]
  [[ "$output" =~ "Dotfile and Tool Management" ]]
}

@test "make work-setup runs setup-work-mac.sh" {
  cat > setup-work-mac.sh <<'EOF'
#!/usr/bin/env bash
echo "Running work setup"
EOF
  chmod +x setup-work-mac.sh

  run make work-setup
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Running work setup" ]]
}

@test "VSCODE_CLI environment variable is passed through" {
  # Update mock install.sh to show VSCODE_CLI
  cat > install.sh << 'EOF'
#!/usr/bin/env bash
echo "CONFIG_FILES: $CONFIG_FILES"
echo "VSCODE_CLI: $VSCODE_CLI"
echo "Arguments: $@"
EOF
  chmod +x install.sh

  VSCODE_CLI=cursor run make vscode install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "VSCODE_CLI: cursor" ]]
}

@test "make with invalid target fails" {
  run make invalid_target
  [ "$status" -ne 0 ]
}

@test "make manifests-generate creates the selected profile manifest directory" {
  run make manifests-generate work
  [ "$status" -eq 0 ]
  [[ "$output" == *"Generating install manifests in .generated/manifests/work"* ]]
  [[ "$output" == *"generate-install-manifests called for .generated/manifests/work with: shared/shell"* ]]
  [ -f ".generated/manifests/work/result.txt" ]
}
