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
  export BORDERS_REPO="$TEST_DIR/missing-borders"

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
printf '%s\n' "$*" >> "$TEST_DIR/brew-call-log"
if [[ "$1" == outdated ]]; then
  [[ "${MOCK_BREW_OUTDATED_FAIL:-}" != 1 ]] || { echo 'outdated check failed' >&2; exit 42; }
  [[ "${MOCK_BREW_NO_UPDATES:-}" != 1 ]] || exit 0
  if [[ "$*" == *--formula* ]]; then
    [[ "${MOCK_BREW_FORMULA_CURRENT:-}" != 1 ]] || exit 0
    echo formula-fixture
  else
    echo cask-fixture
  fi
  exit 0
fi
if [[ "$1" == "tap" && "$#" -eq 1 ]]; then
  if [[ -n "${MOCK_BREW_TAPS:-}" ]]; then
    printf '%s\n' "$MOCK_BREW_TAPS"
  fi
  exit 0
fi
if [[ "$1" == "untap" ]]; then
  printf '%s\n' "$*" > "$TEST_DIR/brew-untap.args"
  echo "brew $*"
  exit 0
fi
if [[ "$1" == "bundle" ]]; then
  shift
  if [[ "$1" == "list" && "$2" == "--cask" ]]; then
    printf '%s\n' brave-browser alfred ghostty
    exit 0
  fi
  if [[ "$1" == "list" && "$2" == "--formula" ]]; then
    printf '%s\n' fzf mise tmux azure/functions/azure-functions-core-tools@4
    exit 0
  fi
  printf "%s\n" "$@" > "${TEST_DIR}/brew-bundle-args.txt"
  printf "%s\t%s\t%s\t%s\n" "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" "${HOMEBREW_NO_ENV_HINTS:-}" "${HOMEBREW_BUNDLE_CASK_SKIP:-}" "${HOMEBREW_BUNDLE_BREW_SKIP:-}" > "${TEST_DIR}/brew-policy-env.txt"
  echo "brew bundle called"
  exit 0
fi
if [[ "$1" == "list" && "$2" == "--cask" ]]; then
  printf '%s\n' brave-browser alfred
  exit 0
fi
if [[ "$1" == "list" && "$2" == "--formula" ]]; then
  printf '%s\n' fzf mise azure-functions-core-tools@4
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
  for script in brew-bundle-install.sh brew-with-policy.sh brew-trust.sh brew-update.sh audit-system-tools.sh install-borders.sh; do
    if [ -f "$REPO_ROOT/scripts/$script" ]; then
      cp "$REPO_ROOT/scripts/$script" scripts/
      chmod +x "scripts/$script"
    fi
  done

  # Copy the Makefile
  cp "$REPO_ROOT/Makefile" .
  mkdir -p skills/verify-dotfiles
  cp "$REPO_ROOT/skills/verify-dotfiles/verify.mk" skills/verify-dotfiles/verify.mk
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

@test "make help honors NO_COLOR and emits no ANSI escapes" {
  run env NO_COLOR=1 make help
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033['* ]]
}

@test "make install runs brew bundle, stow, optional Borders install, and mise install" {
  run make install
  [ "$status" -eq 0 ]
  if [[ "$EXPECTED_BREWFILE" == "Brewfile" ]]; then
    [[ "$output" == *"brew bundle called"* ]]
  else
    [[ "$output" != *"brew bundle called"* ]]
  fi
  [[ "$output" == *"stow.sh called with: --backup-conflicts"* ]]
  if [[ "$EXPECTED_BREWFILE" == "Brewfile" ]]; then
    [[ "$output" == *"Skipping Borders installation"* ]]
  else
    [[ "$output" != *"Skipping Borders installation"* ]]
  fi
  [[ "$output" == *"mise install"* ]]
}

@test "make borders-install installs the local checkout when present" {
  mkdir -p "$BORDERS_REPO"
  touch "$BORDERS_REPO/Makefile"
  cat > "$TEST_DIR/mocks/borders-make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_DIR/borders-make.args"
EOF
  chmod +x "$TEST_DIR/mocks/borders-make"

  run env BORDERS_MAKE_CMD="$TEST_DIR/mocks/borders-make" make borders-install

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing Borders from $BORDERS_REPO"* ]]
  [ "$(cat "$TEST_DIR/borders-make.args")" = "-C $BORDERS_REPO install" ]
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
  run awk -F '\t' '$1 == "" && $2 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
}

@test "make brewfile-install installs only missing formulae and casks" {
  run make brewfile-install
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using brave-browser (installed)"* ]]
  [[ "$output" == *"Using alfred"* ]]
  [[ "$output" == *"Using fzf (installed)"* ]]
  [[ "$output" == *"Using azure/functions/azure-functions-core-tools@4 (installed)"* ]]
  run awk -F '\t' '$3 ~ /(^| )brave-browser( |$)/ && $3 ~ /(^| )alfred( |$)/ { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
  run awk -F '\t' '$4 ~ /(^| )fzf( |$)/ && $4 ~ /(^| )mise( |$)/ { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
  run awk -F '\t' '$4 ~ /(^| )azure\/functions\/azure-functions-core-tools@4( |$)/ { found = 1 } END { exit found ? 0 : 1 }' "$TEST_DIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
}

@test "Homebrew update upgrades installed formulae and casks explicitly" {
  run scripts/brew-update.sh update-all
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew upgrade --formula"* ]]
  [[ "$output" == *"brew upgrade --cask"* ]]
  [[ "$output" != *"Pearcleaner"* ]]
}

@test "Homebrew update offers to retire the old Borders tap" {
  run bash -c 'printf "\n\n\n" | env MOCK_BREW_TAPS=felixkratz/formulae scripts/brew-update.sh update-all'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Retired Borders tap felixkratz/formulae is installed"* ]]
  [[ "$output" == *"brew untap felixkratz/formulae"* ]]
  [[ "$output" == *"Removed retired Homebrew tap felixkratz/formulae"* ]]
}

@test "Homebrew update dry-run reports the old Borders tap without removing it" {
  run env MOCK_BREW_TAPS=felixkratz/formulae scripts/brew-update.sh update-all --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would offer to untap retired Homebrew tap felixkratz/formulae"* ]]
  [[ "$output" != *"brew untap felixkratz/formulae"* ]]
}

@test "Homebrew no-input does not remove the old Borders tap" {
  run env MOCK_BREW_TAPS=felixkratz/formulae scripts/brew-update.sh update-all --no-input
  [ "$status" -eq 0 ]
  [[ "$output" == *"confirmation required"* ]]
  [ ! -f "$TEST_DIR/brew-untap.args" ]
}

@test "make stow calls stow.sh" {
  run make stow
  [ "$status" -eq 0 ]
  [[ "$output" == *"stow.sh called with:"* ]]
  [[ "$output" != *"--backup-conflicts"* ]]
}

@test "make mise-install runs mise install" {
  run make mise-install
  [ "$status" -eq 0 ]
  [[ "$output" =~ "mise install" ]]
}

@test "mise bumps default to a seven-day cooldown" {
  run make mise-bump
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise upgrade --bump --minimum-release-age 7d"* ]]
  [[ "$output" != *"--dry-run"* ]]
}

@test "mise emergency preview scopes tools and overrides age for one invocation" {
  run make mise-bump-preview MISE_MINIMUM_RELEASE_AGE=0d MISE_BUMP_TOOLS="node bun"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise upgrade --bump --minimum-release-age 0d --dry-run node bun"* ]]
  [[ "$output" != *"upgrade completed"* ]]

  run make mise-bump MISE_MINIMUM_RELEASE_AGE=0d MISE_BUMP_TOOLS="node bun"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise upgrade --bump --minimum-release-age 0d node bun"* ]]
  [[ "$output" != *"--dry-run"* ]]

  run make mise-bump-preview
  [ "$status" -eq 0 ]
  [[ "$output" == *"mise upgrade --bump --minimum-release-age 7d --dry-run"* ]]
  [[ "$output" != *"node bun"* ]]
}

@test "make update uses the shared Homebrew update module and checks mise pins" {
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
  if [[ "$EXPECTED_BREWFILE" == "Brewfile" ]]; then
    [[ "$output" =~ "shared Homebrew update module: update-all" ]]
  else
    [[ "$output" != *"shared Homebrew update module: update-all"* ]]
  fi
  [[ "$output" =~ "mise outdated --bump" ]]

  if [[ "$EXPECTED_BREWFILE" == "Brewfile" ]]; then
    run grep -qx "update-all" "$TEST_DIR/brew-update-calls.txt"
    [ "$status" -eq 0 ]
  else
    [ ! -f "$TEST_DIR/brew-update-calls.txt" ]
  fi
}

@test "make audit runs both package drift and deep system audits" {
  cat > scripts/audit-installed.sh <<'EOF'
#!/usr/bin/env bash
echo "package drift audit called"
EOF
  chmod +x scripts/audit-installed.sh
  cat > scripts/audit-system-tools.sh <<'EOF'
#!/usr/bin/env bash
echo "deep system audit called"
EOF
  chmod +x scripts/audit-system-tools.sh

  run make audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"package drift audit called"* ]]
  [[ "$output" == *"deep system audit called"* ]]
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

@test "Homebrew upgrade accepts Enter and prevents automatic app quitting" {
  run bash -c 'printf "\n\n" | scripts/brew-update.sh update-all'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Y/n]"* ]]
  [[ "$output" == *"brew upgrade --formula --yes"* ]]
  [[ "$output" == *"brew upgrade --cask --no-quit --yes"* ]]
}

@test "Homebrew upgrade respects no and EOF" {
  run bash -c 'printf "n\n" | scripts/brew-update.sh update-all'
  [ "$status" -eq 0 ]
  [[ "$output" != *"--yes"* ]]
}

@test "Homebrew dry run only previews upgrades" {
  run scripts/brew-update.sh update-all --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" != *"brew update"* ]]
  [[ "$output" != *"brew cleanup"* ]]
  [[ "$output" != *"--yes"* ]]
  [[ "$output" != *"[Y/n]"* ]]
}

@test "Homebrew no-input explicitly approves upgrades" {
  run scripts/brew-update.sh update-all --no-input
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew upgrade --cask --no-quit --yes"* ]]
  [[ "$output" != *"[Y/n]"* ]]
}

@test "Homebrew update rejects unknown options" {
  run scripts/brew-update.sh update-all --unknown
  [ "$status" -eq 2 ]
}

@test "Makefile exposes the repeatable update and emergency preview" {
  cat > scripts/update-all.sh <<'EOF'
#!/usr/bin/env bash
printf 'update-all args: %s\n' "$*"
EOF
  chmod +x scripts/update-all.sh

  run make update-all UPDATE_FLAGS="--no-cooldown --no-input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"update-all args: --no-cooldown --no-input"* ]]

  run make update-all-preview UPDATE_FLAGS="--no-cooldown"
  [ "$status" -eq 0 ]
  [[ "$output" == *"update-all args: --dry-run --no-cooldown"* ]]
}

@test "component Make targets expose cooldown preview and noninteractive controls" {
  cat > scripts/update-all.sh <<'EOF'
#!/usr/bin/env bash
printf 'update-all args: %s\n' "$*"
EOF
  chmod +x scripts/update-all.sh

  for component in brew mise dependencies mas rust; do
    run make "update-$component" NO_COOLDOWN=1 NO_INPUT=1 DRY_RUN=1
    [ "$status" -eq 0 ]
    [[ "$output" == *"update-all args: --only $component --no-cooldown --no-input --dry-run"* ]]
  done

  run make update-brew
  [ "$status" -eq 0 ]
  [[ "$output" == *"update-all args: --only brew"* ]]
  [[ "$output" != *"--no-cooldown"* ]]
  [[ "$output" != *"--no-input"* ]]

  run make update-all-preview NO_COOLDOWN=1
  [ "$status" -eq 0 ]
  [[ "$output" == *"update-all args: --dry-run --no-cooldown"* ]]
}

@test "Homebrew does not prompt upgrade or clean when no packages are outdated" {
  run env MOCK_BREW_NO_UPDATES=1 scripts/brew-update.sh update-all
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Homebrew formulae upgrades available."* ]]
  [[ "$output" == *"No Homebrew casks upgrades available."* ]]
  [[ "$output" == *"Homebrew packages already up to date."* ]]
  [[ "$output" != *"[Y/n]"* ]]
  [[ "$output" != *"upgrades completed"* ]]
  run grep -E '^upgrade |^cleanup$' "$TEST_DIR/brew-call-log"
  [ "$status" -eq 1 ]
}

@test "Homebrew prompts only for the group with available upgrades" {
  run bash -c 'printf "y\n" | env MOCK_BREW_FORMULA_CURRENT=1 scripts/brew-update.sh update-all'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Upgrade Homebrew casks? [Y/n]"* ]]
  [[ "$output" != *"Upgrade Homebrew formulae?"* ]]
  run grep '^upgrade --formula' "$TEST_DIR/brew-call-log"
  [ "$status" -eq 1 ]
}

@test "Homebrew cannot report current packages when the outdated check fails" {
  run env MOCK_BREW_OUTDATED_FAIL=1 scripts/brew-update.sh update-all --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"outdated check failed"* ]]
  [[ "$output" != *"packages already up to date"* ]]
  [[ "$output" != *"upgrades completed"* ]]
}
