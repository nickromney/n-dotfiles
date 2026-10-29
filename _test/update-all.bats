#!/usr/bin/env bats

setup() {
  REAL_UV="$(mise which uv 2>/dev/null || command -v uv || true)"
  export REAL_UV
  TEST_ROOT="$BATS_TEST_TMPDIR/update"
  mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/mise/.config/mise" "$TEST_ROOT/home/.config/mise" "$TEST_ROOT/bin"
  export HOME="$TEST_ROOT/home"
  export CALL_LOG="$TEST_ROOT/calls"
  export PATH="$TEST_ROOT/bin:$PATH"
  local repo_root
  repo_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cp "$repo_root/scripts/update-all.sh" "$TEST_ROOT/scripts/"
  cp "$repo_root/scripts/brew-update.sh" "$TEST_ROOT/scripts/"
  cp "$repo_root/scripts/brew-with-policy.sh" "$TEST_ROOT/scripts/"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/scripts/brew-trust.sh"
  chmod +x "$TEST_ROOT/scripts/brew-trust.sh"
  touch "$TEST_ROOT/uv.lock"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/bin/browser-tools"
  chmod +x "$TEST_ROOT/bin/browser-tools"
  touch "$TEST_ROOT/mise/.config/mise/config.toml"
  ln -s "$TEST_ROOT/mise/.config/mise/config.toml" "$HOME/.config/mise/config.toml"
  for tool in mise brew mas rustup; do
    cat > "$TEST_ROOT/bin/$tool" <<'MOCK'
#!/usr/bin/env bash
name="${0##*/}"
if [[ "$name" == brew ]]; then
  printf 'brew-greedy=%s/%s\n' "${HOMEBREW_UPGRADE_GREEDY-unset}" "${HOMEBREW_UPGRADE_GREEDY_CASKS-unset}" >> "$CALL_LOG"
fi
if [[ "$name $*" == 'brew outdated --quiet '* ]]; then
  echo outdated-fixture
  exit 0
fi
if [[ "${REAL_UV_TEST:-}" == 1 && "$name $*" == 'mise exec -- uv '* && "$4" != audit ]]; then
  shift 3
  exec "$REAL_UV" "$@"
fi
if [[ "${PARTIAL_BUN:-}" == 1 && "$name $*" == *'bun update'* ]]; then
  echo 'warn: ws was not checked for updates: DNSResolveFailed'
fi
if [[ "${PARTIAL_MISE:-}" == 1 && "$name $*" == 'mise upgrade '* ]]; then
  echo 'mise WARN Error getting latest version for node: failed to resolve DNS'
fi
if [[ "${UV_GRAPH_CHANGE:-}" == 1 && "$name $*" == 'mise exec -- uv export '* ]]; then
  cat uv.lock
  exit 0
fi
if [[ "${UV_GRAPH_CHANGE:-}" == 1 && "$name $*" == 'mise exec -- uv lock --offline' ]]; then
  echo changed-dependency-set > uv.lock
  exit 0
fi
if [[ "${PENDING_MAS:-}" == 1 && "$name $*" == 'mas outdated' ]]; then
  echo '803453959 Slack (old -> new)'
fi
if [[ "${PENDING_BREW:-}" == 1 && "$name $*" == 'brew outdated --quiet' ]]; then
  echo brave-browser
fi
printf '%s %s\n' "$name" "$*" >> "$CALL_LOG"
if [[ "$name" == mise ]]; then
  printf 'mise-auto-install=%s/%s\n' "${MISE_AUTO_INSTALL:-unset}" "${MISE_EXEC_AUTO_INSTALL:-unset}" >> "$CALL_LOG"
fi
if [[ "$name" == brew && "$1" == upgrade && "$*" != *--dry-run* ]]; then
  printf 'brew-cleanup=%s\n' "${HOMEBREW_NO_INSTALL_CLEANUP:-unset}" >> "$CALL_LOG"
fi
if [[ -n "${FAIL_MATCH:-}" && "$name $*" == *"$FAIL_MATCH"* ]]; then
  echo "simulated failure: $name $*" >&2
  exit 42
fi
MOCK
    chmod +x "$TEST_ROOT/bin/$tool"
  done
  printf '#!/usr/bin/env bash\necho Darwin\n' > "$TEST_ROOT/bin/uname"
  chmod +x "$TEST_ROOT/bin/uname"
  cd "$TEST_ROOT" || return 1
}

@test "update-all preview uses seven-day defaults and only read-only manager commands" {
  run scripts/update-all.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Preview completed"* ]]
  run cat "$CALL_LOG"
  [[ "$output" == *"upgrade --global --bump --no-prune --minimum-release-age 7d --dry-run"* ]]
  [[ "$output" == *"bun update --latest --minimum-release-age 604800 --dry-run"* ]]
  [[ "$output" == *"uv lock --upgrade --exclude-newer 7 days --dry-run"* ]]
  [[ "$output" == *"brew upgrade --cask --no-quit --dry-run"* ]]
  [[ "$output" != *"--greedy"* ]]
  [[ "$output" == *"mas outdated"* ]]
  [[ "$output" == *"rustup check"* ]]
  [[ "$output" == *"mise-auto-install=0/0"* ]]
  [[ "$output" != *"brew update"* ]]
  [[ "$output" != *"mas upgrade"* ]]
  [[ "$output" != *"rustup update"* ]]
  [[ "$output" != *"brew cleanup"* ]]
}

@test "emergency apply overrides all supported cooldowns and verifies mise upgrades" {
  run scripts/update-all.sh --no-cooldown --no-input
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"upgrade --global --bump --no-prune --minimum-release-age 0d"* ]]
  [[ "$output" == *"--minimum-release-age 0d --dry-run-code"* ]]
  [[ "$output" == *"bun update --latest --minimum-release-age 0"* ]]
  [[ "$output" == *"uv lock --upgrade --exclude-newer 0 days"* ]]
  [[ "$output" == *"mas upgrade"* ]]
  [[ "$output" == *"rustup update"* ]]
  [[ "$output" == *"brew-cleanup=1"* ]]
  [[ "$output" != *"brew cleanup"* ]]

  run scripts/update-all.sh --dry-run --only mise
  [ "$status" -eq 0 ]
  run tail -n 2 "$CALL_LOG"
  [[ "$output" == *"--minimum-release-age 7d --dry-run"* ]]
}

@test "dependency failure is nonzero and does not suppress independent steps" {
  run env FAIL_MATCH='bun update' scripts/update-all.sh --only dependencies --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAILED: JavaScript dependencies"* ]]
  [[ "$output" == *"OK: Python dependency lockfile"* ]]
  [[ "$output" == *"Update incomplete: 1 step(s) failed"* ]]
  [[ "$output" != *"Selected managed updates completed"* ]]
}

@test "mise verification failure makes the update incomplete" {
  run env FAIL_MATCH='--dry-run-code' scripts/update-all.sh --only mise --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAILED: Mise tools and pins"* ]]
}

@test "Homebrew helper propagates upgrade failures through coordinator" {
  run env FAIL_MATCH='brew upgrade --formula' scripts/update-all.sh --only brew --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAILED: Homebrew packages"* ]]
  [[ "$output" != *"Homebrew updated"* ]]
}

@test "mise refuses to update an unrelated global config" {
  rm "$HOME/.config/mise/config.toml"
  touch "$HOME/.config/mise/config.toml"
  run scripts/update-all.sh --only mise --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"not stowed from this repository"* ]]
  [ ! -e "$CALL_LOG" ]
}

@test "update-all rejects invalid arguments before contacting package managers" {
  for args in '--only' '--only unknown' '--unknown'; do
    # Intentional splitting exercises the public argv contract.
    # shellcheck disable=SC2086
    run scripts/update-all.sh $args
    [ "$status" -eq 2 ]
  done
  [ ! -e "$CALL_LOG" ]
}

@test "update-all refuses unattended mutation without explicit approval" {
  run bash -c 'scripts/update-all.sh </dev/null'
  [ "$status" -ne 0 ]
  [[ "$output" == *"--no-input"* ]]
  [ ! -e "$CALL_LOG" ]
}

@test "failed JavaScript audit prevents rebuilding the compiled browser tool" {
  run env FAIL_MATCH='bun audit' scripts/update-all.sh --only dependencies --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAILED: JavaScript dependencies"* ]]
  run cat "$CALL_LOG"
  [[ "$output" != *"build-browser-tools.sh"* ]]
  [[ "$output" == *"uv audit --locked"* ]]
}

@test "a partial Bun registry check cannot report a successful update" {
  run env PARTIAL_BUN=1 scripts/update-all.sh --only dependencies --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"Update incomplete; check the registry errors"* ]]
  run cat "$CALL_LOG"
  [[ "$output" != *"build-browser-tools.sh"* ]]
}

@test "real uv emergency update leaves the normal locked gate usable" {
  [[ -n "$REAL_UV" ]] || skip 'uv is unavailable'
  rm uv.lock
  cat > pyproject.toml <<'TOML'
[project]
name = "update-fixture"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = []
[tool.uv]
package = false
exclude-newer = "7 days"
TOML
  run env REAL_UV_TEST=1 UV_OFFLINE=1 UV_CACHE_DIR="$TEST_ROOT/cache" UV_PYTHON_DOWNLOADS=never \
    scripts/update-all.sh --only dependencies --no-cooldown --no-input
  [ "$status" -eq 0 ]
  run env UV_CACHE_DIR="$TEST_ROOT/cache" "$REAL_UV" lock --check --offline
  [ "$status" -eq 0 ]
  run cat uv.lock
  [[ "$output" == *'exclude-newer-span = "P7D"'* ]]
}

@test "Homebrew cannot report completion while a running cask remains outdated" {
  run env PENDING_BREW=1 scripts/update-all.sh --only brew --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"Homebrew still reports outdated packages"* ]]
  [[ "$output" == *"brave-browser"* ]]
  [[ "$output" != *"Selected managed updates completed"* ]]
}

@test "Mac App Store cannot report completion while apps remain outdated" {
  run env PENDING_MAS=1 scripts/update-all.sh --only mas --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"Mac App Store apps still need updates"* ]]
  [[ "$output" != *"Selected managed updates completed"* ]]
}

@test "uv preserves the emergency lockfile if restoring cooldown would change dependencies" {
  printf 'emergency-dependency-set\n' > uv.lock
  run env UV_GRAPH_CHANGE=1 scripts/update-all.sh --only dependencies --no-cooldown --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"uv.lock was retained"* ]]
  [ "$(cat uv.lock)" = emergency-dependency-set ]
}

@test "mise cannot claim success after silently falling back to cached registry data" {
  run env PARTIAL_MISE=1 scripts/update-all.sh --only mise --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAILED: Mise tools and pins"* ]]
  [[ "$output" != *"Preview completed"* ]]
}

@test "native app channels are protected from inherited Homebrew greedy settings" {
  run env HOMEBREW_UPGRADE_GREEDY=1 HOMEBREW_UPGRADE_GREEDY_CASKS=1password \
    scripts/update-all.sh --only brew --no-input
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"brew-greedy=unset/unset"* ]]
  [[ "$output" != *"brew-greedy=1/1password"* ]]
  [[ "$output" != *"--greedy"* ]]
}

@test "failed mise updates prevent rebuilding dependencies with the old runtime" {
  run env FAIL_MATCH='mise upgrade' scripts/update-all.sh --no-input
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKIP: dependency updates and rebuilds because the mise step failed."* ]]
  [[ "$output" == *"OK: Mac App Store apps"* ]]
  [[ "$output" == *"OK: Rust toolchains"* ]]
  run cat "$CALL_LOG"
  [[ "$output" != *"bun update"* ]]
  [[ "$output" != *"uv lock"* ]]
  [[ "$output" != *"build-browser-tools.sh"* ]]
}
