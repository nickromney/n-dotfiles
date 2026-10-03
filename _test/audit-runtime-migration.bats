#!/usr/bin/env bats

setup() {
  export TEST_HOME="$BATS_TEST_TMPDIR/home"
  export TEST_REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_HOME" "$TEST_REPO/scripts" "$TEST_REPO/aws/.aws/cli/cache"
  if [[ -f "$BATS_TEST_DIRNAME/../scripts/migrate-runtime-roots.sh" ]]; then
    cp "$BATS_TEST_DIRNAME/../scripts/migrate-runtime-roots.sh" "$TEST_REPO/scripts/"
  fi
  cp "$BATS_TEST_DIRNAME/../stow.sh" "$TEST_REPO/"
  cp "$BATS_TEST_DIRNAME/../aws/.stow-local-ignore" "$TEST_REPO/aws/"
  printf '%s\n' '#!/bin/sh' > "$TEST_REPO/aws/.aws/aws-1password"
  printf '%s\n' 'local profile' > "$TEST_REPO/aws/.aws/config"
  printf '%s\n' 'local session' > "$TEST_REPO/aws/.aws/cli/cache/session.db"
  ln -s ../repo/aws/.aws "$TEST_HOME/.aws"
}

@test "runtime migration preserves AWS state outside the repo and remains idempotent" {
  run env HOME="$TEST_HOME" "$TEST_REPO/scripts/migrate-runtime-roots.sh" --execute aws

  [ "$status" -eq 0 ]
  [ ! -L "$TEST_HOME/.aws" ]
  [ -L "$TEST_HOME/.aws/aws-1password" ]
  [ "$(cat "$TEST_HOME/.aws/config")" = 'local profile' ]
  [ "$(cat "$TEST_HOME/.aws/cli/cache/session.db")" = 'local session' ]
  [ "$(cat "$TEST_REPO/aws/.aws/cli/cache/session.db")" = 'local session' ]
  [ "$(cat "$TEST_HOME/.n-dotfiles-runtime-backups"/*/aws/files/config)" = 'local profile' ]
  printf '%s\n' 'new session' > "$TEST_HOME/.aws/cli/cache/session.db"
  [ "$(cat "$TEST_REPO/aws/.aws/cli/cache/session.db")" = 'local session' ]

  run env HOME="$TEST_HOME" "$TEST_REPO/scripts/migrate-runtime-roots.sh" --execute aws
  [ "$status" -eq 0 ]
  [[ "$output" == *'already machine-local'* ]]
  [ "$(cat "$TEST_HOME/.aws/cli/cache/session.db")" = 'new session' ]

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" aws
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/.aws/cli/cache/session.db")" = 'new session' ]
}

@test "runtime migration defaults to preview without creating backups or replacing links" {
  run env HOME="$TEST_HOME" "$TEST_REPO/scripts/migrate-runtime-roots.sh" aws

  [ "$status" -eq 0 ]
  [ -L "$TEST_HOME/.aws" ]
  [ ! -e "$TEST_HOME/.n-dotfiles-runtime-backups" ]
  [ "$(cat "$TEST_HOME/.aws/config")" = 'local profile' ]
  [[ "$output" == *'would copy, verify, back up, and detach'* ]]
}

@test "runtime migration preserves GitHub authentication and Nushell history locally" {
  mkdir -p "$TEST_REPO/gh/.config/gh" "$TEST_HOME/.config"
  cp "$BATS_TEST_DIRNAME/../gh/.stow-local-ignore" "$TEST_REPO/gh/"
  printf '%s\n' 'git_protocol: ssh' > "$TEST_REPO/gh/.config/gh/config.yml"
  printf '%s\n' 'local auth fixture' > "$TEST_REPO/gh/.config/gh/hosts.yml"
  ln -s ../../repo/gh/.config/gh "$TEST_HOME/.config/gh"
  local relative='Library/Application Support/nushell'
  mkdir -p "$TEST_REPO/nushell/$relative" "$TEST_HOME/Library/Application Support"
  cp "$BATS_TEST_DIRNAME/../nushell/.stow-local-ignore" "$TEST_REPO/nushell/"
  printf '%s\n' '# portable config' > "$TEST_REPO/nushell/$relative/config.nu"
  printf '%s\n' 'private history' > "$TEST_REPO/nushell/$relative/history.sqlite3"
  ln -s "../../../repo/nushell/$relative" "$TEST_HOME/$relative"

  run env HOME="$TEST_HOME" "$TEST_REPO/scripts/migrate-runtime-roots.sh" --execute gh nushell

  [ "$status" -eq 0 ]
  [ ! -L "$TEST_HOME/.config/gh" ]
  [ -L "$TEST_HOME/.config/gh/config.yml" ]
  [ ! -L "$TEST_HOME/.config/gh/hosts.yml" ]
  [ "$(cat "$TEST_HOME/.config/gh/hosts.yml")" = 'local auth fixture' ]
  [ ! -L "$TEST_HOME/$relative" ]
  [ -L "$TEST_HOME/$relative/config.nu" ]
  [ ! -L "$TEST_HOME/$relative/history.sqlite3" ]
  [ "$(cat "$TEST_HOME/$relative/history.sqlite3")" = 'private history' ]

  run env HOME="$TEST_HOME" "$TEST_REPO/stow.sh" gh nushell
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/.config/gh/hosts.yml")" = 'local auth fixture' ]
  [ "$(cat "$TEST_HOME/$relative/history.sqlite3")" = 'private history' ]
}

@test "runtime migration refuses relative links whose meaning would change after detaching" {
  printf '%s\n' 'external referenced data' > "$TEST_REPO/aws/shared.txt"
  ln -s ../shared.txt "$TEST_REPO/aws/.aws/reference"

  run env HOME="$TEST_HOME" "$TEST_REPO/scripts/migrate-runtime-roots.sh" --execute aws

  [ "$status" -ne 0 ]
  [ -L "$TEST_HOME/.aws" ]
  [ ! -e "$TEST_HOME/.n-dotfiles-runtime-backups" ]
  [ "$(cat "$TEST_HOME/.aws/reference")" = 'external referenced data' ]
  [[ "$output" == *'relative symlink'* ]]
}
