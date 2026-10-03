#!/usr/bin/env bats

setup() {
  export TEST_ROOT
  TEST_ROOT="$(mktemp -d)"
  export TEST_HOME="$TEST_ROOT/home"
  export TEST_REPO="$TEST_ROOT/repo"
  export DOTFILES_ROOT="$BATS_TEST_DIRNAME/.."
  mkdir -p "$TEST_HOME" "$TEST_REPO"
  cp "$DOTFILES_ROOT/stow.sh" "$TEST_REPO/stow.sh"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

copy_package_ignore() {
  local package=$1
  if [[ -f "$DOTFILES_ROOT/$package/.stow-local-ignore" ]]; then
    cp "$DOTFILES_ROOT/$package/.stow-local-ignore" "$TEST_REPO/$package/"
  fi
}

@test "stow keeps AWS credentials and caches local while exposing its helper" {
  mkdir -p "$TEST_REPO/aws/.aws/cli/cache"
  cp "$DOTFILES_ROOT/aws/.aws/aws-1password" "$TEST_REPO/aws/.aws/"
  printf '%s\n' 'private AWS configuration' > "$TEST_REPO/aws/.aws/config"
  printf '%s\n' 'private AWS credentials' > "$TEST_REPO/aws/.aws/credentials"
  printf '%s\n' 'private cached session' > "$TEST_REPO/aws/.aws/cli/cache/session.db"
  copy_package_ignore aws

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" aws

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.aws/aws-1password" ]
  [ ! -L "$TEST_HOME/.aws" ]
  [ ! -e "$TEST_HOME/.aws/config" ]
  [ ! -e "$TEST_HOME/.aws/credentials" ]
  [ ! -e "$TEST_HOME/.aws/cli/cache/session.db" ]

  mkdir -p "$TEST_HOME/.aws/cli/cache"
  printf '%s\n' 'new machine session' > "$TEST_HOME/.aws/cli/cache/new.json"
  [ ! -e "$TEST_REPO/aws/.aws/cli/cache/new.json" ]

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" aws
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/.aws/cli/cache/new.json")" = 'new machine session' ]
}

@test "repository ignores machine credentials even without a global Git ignore" {
  local path
  for path in \
    .env .env.production .claude/settings.local.json \
    aws/.aws/config aws/.aws/credentials aws/.aws/cli/cache/new.json \
    aws/.aws/sso/cache/new.json aws/.aws/login/cache/new.json gh/.config/gh/hosts.yml \
    ssh/.ssh/config ssh/.ssh/config.d/local/server.conf ssh/.ssh/custom_key; do
    run git -C "$DOTFILES_ROOT" -c core.excludesfile=/dev/null \
      check-ignore --no-index "$path"
    [ "$status" -eq 0 ]
  done

  for path in .env.example ssh/.ssh/config.example \
    ssh/.ssh/config.d/local/gitea.conf.example; do
    run git -C "$DOTFILES_ROOT" -c core.excludesfile=/dev/null \
      check-ignore --no-index "$path"
    [ "$status" -eq 1 ]
  done
}

@test "stow exposes GitHub CLI preferences without routing authentication into git" {
  mkdir -p "$TEST_REPO/gh/.config/gh"
  printf '%s\n' 'git_protocol: ssh' > "$TEST_REPO/gh/.config/gh/config.yml"
  printf '%s\n' 'private OAuth token' > "$TEST_REPO/gh/.config/gh/hosts.yml"
  copy_package_ignore gh

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" gh

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.config/gh/config.yml" ]
  [ ! -L "$TEST_HOME/.config" ]
  [ ! -L "$TEST_HOME/.config/gh" ]
  [ ! -e "$TEST_HOME/.config/gh/hosts.yml" ]
  printf '%s\n' 'new local OAuth token' > "$TEST_HOME/.config/gh/hosts.yml"
  [ "$(cat "$TEST_REPO/gh/.config/gh/hosts.yml")" = 'private OAuth token' ]
}

@test "stow never installs private SSH material adopted into its template package" {
  mkdir -p "$TEST_REPO/ssh/.ssh/config.d"
  printf '%s\n' 'private host configuration' > "$TEST_REPO/ssh/.ssh/config"
  printf '%s\n' 'private profile' > "$TEST_REPO/ssh/.ssh/config.d/local.conf"
  printf '%s\n' 'private key' > "$TEST_REPO/ssh/.ssh/custom_key"
  copy_package_ignore ssh

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" --adopt ssh

  [ "$status" -eq 0 ]
  [ ! -L "$TEST_HOME/.ssh" ]
  [ ! -e "$TEST_HOME/.ssh/config" ]
  [ ! -e "$TEST_HOME/.ssh/config.d/local.conf" ]
  [ ! -e "$TEST_HOME/.ssh/custom_key" ]
}

@test "stow refuses to unfold legacy AWS runtime state before changing other packages" {
  mkdir -p "$TEST_REPO/aws/.aws/cli/cache" "$TEST_REPO/zsh"
  cp "$DOTFILES_ROOT/aws/.aws/aws-1password" "$TEST_REPO/aws/.aws/"
  printf '%s\n' 'existing local account' > "$TEST_REPO/aws/.aws/config"
  printf '%s\n' 'existing cached session' > "$TEST_REPO/aws/.aws/cli/cache/session.db"
  printf '%s\n' 'repository shell' > "$TEST_REPO/zsh/.zshrc"
  copy_package_ignore aws
  ln -s ../repo/aws/.aws "$TEST_HOME/.aws"

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" zsh aws

  [ "$status" -eq 1 ]
  [[ "$output" == *'machine-local state'* ]]
  [ -L "$TEST_HOME/.aws" ]
  [ "$(cat "$TEST_HOME/.aws/config")" = 'existing local account' ]
  [ "$(cat "$TEST_HOME/.aws/cli/cache/session.db")" = 'existing cached session' ]
  [ ! -e "$TEST_HOME/.zshrc" ]
}

@test "AWS credential process selects the invoking account on every platform" {
  local mock_bin="$TEST_ROOT/bin"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/id" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'fixture-user'
EOF
  cat > "$mock_bin/op" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  'read op://CLI/AWSCredsUsernamefixture-user/ACCESS_KEY') printf '%s\n' 'fixture-access' ;;
  'read op://CLI/AWSCredsUsernamefixture-user/SECRET_KEY') printf '%s\n' 'fixture-secret' ;;
  *) echo 'Unexpected credential selector' >&2; exit 1 ;;
esac
EOF
  chmod +x "$mock_bin/id" "$mock_bin/op"

  run env HOME="$TEST_HOME" PATH="$mock_bin:$PATH" AWS_1PASSWORD_USER= \
    "$DOTFILES_ROOT/aws/.aws/aws-1password"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.AccessKeyId')" = fixture-access ]
  [ "$(printf '%s' "$output" | jq -r '.SecretAccessKey')" = fixture-secret ]
  [ "$(printf '%s' "$output" | jq -r '.Version')" = 1 ]
}

@test "Nushell mise integration preserves the invoking machine PATH" {
  local mock_bin="$TEST_ROOT/bin" nu_bin mise_file
  nu_bin="$(mise which nu 2>/dev/null || command -v nu)"
  mise_file="$DOTFILES_ROOT/nushell/Library/Application Support/nushell/vendor/autoload/mise.nu"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/mise" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == hook-env ]]; then
  exit 0
fi
printf '%s\n' 'fixture-mise'
EOF
  chmod +x "$mock_bin/mise"

  run env HOME="$TEST_HOME" PATH="$mock_bin:/usr/bin:/bin" \
    EXPECTED_MISE_BIN="$mock_bin" "$nu_bin" -n -c \
    "source '$mise_file'; print (\$env.PATH | any {|p| \$p == \$env.EXPECTED_MISE_BIN}); print (^mise version)"

  [ "$status" -eq 0 ]
  [ "$output" = $'true\nfixture-mise' ]
}

@test "stow keeps Nushell history in the machine data directory" {
  local relative='Library/Application Support/nushell'
  mkdir -p "$TEST_REPO/nushell/$relative"
  printf '%s\n' '# repository shell config' > "$TEST_REPO/nushell/$relative/config.nu"

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" nushell

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/$relative/config.nu" ]
  [ ! -L "$TEST_HOME/Library" ]
  [ ! -L "$TEST_HOME/$relative" ]
  printf '%s\n' 'private command history' > "$TEST_HOME/$relative/history.sqlite3"
  [ ! -e "$TEST_REPO/nushell/$relative/history.sqlite3" ]
}

@test "stow excludes Nushell histories already present in its source tree" {
  local relative='Library/Application Support/nushell'
  mkdir -p "$TEST_REPO/nushell/$relative"
  printf '%s\n' '# repository shell config' > "$TEST_REPO/nushell/$relative/config.nu"
  printf '%s\n' 'old private history' > "$TEST_REPO/nushell/$relative/history.txt"
  printf '%s\n' 'old private database' > "$TEST_REPO/nushell/$relative/history.sqlite3"
  printf '%s\n' 'old private journal' > "$TEST_REPO/nushell/$relative/history.sqlite3-wal"
  printf '%s\n' 'old private shared memory' > "$TEST_REPO/nushell/$relative/history.sqlite3-shm"
  mkdir -p "$TEST_HOME/$relative"
  printf '%s\n' 'current private history' > "$TEST_HOME/$relative/history.txt"
  copy_package_ignore nushell

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" nushell

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/$relative/config.nu" ]
  [ "$(cat "$TEST_HOME/$relative/history.txt")" = 'current private history' ]
  [ ! -e "$TEST_HOME/$relative/history.sqlite3" ]
  [ ! -e "$TEST_HOME/$relative/history.sqlite3-wal" ]
  [ ! -e "$TEST_HOME/$relative/history.sqlite3-shm" ]
}

@test "stow preserves an unrelated regular n-borders daemon without a managed LaunchAgent" {
  local mock_bin="$TEST_ROOT/bin"
  mkdir -p "$mock_bin" "$TEST_REPO/macos-borders/.config/borders" "$TEST_HOME/.local/bin"
  printf '%s\n' '# repository borders' > "$TEST_REPO/macos-borders/.config/borders/borders.conf"
  printf '%s\n' 'user-owned daemon' > "$TEST_HOME/.local/bin/n-borders-daemon"
  printf '%s\n' '#!/usr/bin/env bash' 'echo Darwin' > "$mock_bin/uname"
  chmod +x "$mock_bin/uname"

  run env HOME="$TEST_HOME" PATH="$mock_bin:$PATH" "$TEST_REPO/stow.sh" macos-borders

  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.local/bin/n-borders-daemon" ]
  [ "$(cat "$TEST_HOME/.local/bin/n-borders-daemon")" = 'user-owned daemon' ]
}
