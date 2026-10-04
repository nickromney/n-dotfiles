#!/usr/bin/env bats
# shellcheck disable=SC2016  # Mock commands expand their environment at runtime.

setup() {
  # Keep the YAML parser usable after HOME is replaced by the fixture.
  local yq_binary
  yq_binary="$(mise which yq 2>/dev/null || command -v yq || true)"
  AUDIT_DIR="$(mktemp -d)"
  export AUDIT_DIR
  export HOME="$AUDIT_DIR/home"
  export PATH="$AUDIT_DIR/bin:$PATH"
  mkdir -p "$HOME" "$AUDIT_DIR/bin"
  [[ -z "$yq_binary" ]] || ln -s "$yq_binary" "$AUDIT_DIR/bin/yq"
}

teardown() {
  rm -rf "$AUDIT_DIR"
}

mock_unavailable_password_items() {
  cat > "$AUDIT_DIR/bin/op" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "account list" ]] && exit 0
printf 'partial response\n'
exit 1
EOF
  chmod +x "$AUDIT_DIR/bin/op"
}

@test "macOS dry-run leaves accessibility preferences unchanged" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  cat > "$AUDIT_DIR/config.yaml" <<'EOF'
system:
  reduce_transparency: true
EOF
  cat > "$AUDIT_DIR/bin/defaults" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "read" ]]; then
  echo 0
else
  echo "$*" >> "$AUDIT_DIR/preferences-written"
fi
EOF
  chmod +x "$AUDIT_DIR/bin/defaults"

  run "$BATS_TEST_DIRNAME/../_macos/macos.sh" --dry-run --no-input "$AUDIT_DIR/config.yaml"

  [ "$status" -eq 0 ]
  [ ! -e "$AUDIT_DIR/preferences-written" ]
  [[ "$output" == *"Would change Reduce transparency"* ]]
}

@test "failed SSH config refresh preserves working files and reports failure" {
  mock_unavailable_password_items
  mkdir -p "$HOME/.ssh/config.d"
  printf 'Host preserved\n  HostName original.example\n' > "$HOME/.ssh/config"
  printf 'Host existing-profile\n' > "$HOME/.ssh/config.d/personal.conf"

  run "$BATS_TEST_DIRNAME/../setup-ssh-from-1password.sh" --profile personal --force --no-input

  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/.ssh/config")" = $'Host preserved\n  HostName original.example' ]
  [ "$(cat "$HOME/.ssh/config.d/personal.conf")" = 'Host existing-profile' ]
}

@test "failed public-key refresh preserves the existing key" {
  mock_unavailable_password_items
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 existing-key\n' > "$HOME/.ssh/personal_github_authentication.pub"

  run "$BATS_TEST_DIRNAME/../setup-ssh-from-1password.sh" --profile personal --force --no-input

  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/.ssh/personal_github_authentication.pub")" = 'ssh-ed25519 existing-key' ]
}

@test "failed work Git config refresh preserves the existing include and reports failure" {
  mock_unavailable_password_items
  mkdir -p "$HOME/Developer/work"
  printf '[user]\n  email = existing@example.com\n' > "$HOME/Developer/work/.gitconfig_include"

  run "$BATS_TEST_DIRNAME/../setup-gitconfig-from-1password.sh"

  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/Developer/work/.gitconfig_include")" = $'[user]\n  email = existing@example.com' ]
}

@test "work Git config stays private and its contents are absent from setup output" {
  cat > "$AUDIT_DIR/git-note" <<'EOF'
[url "https://private-org.example/"]
  insteadOf = https://source.example/
[user]
  email = confidential-work@example.com
EOF
  cat > "$AUDIT_DIR/bin/op" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "account list" ]] && exit 0
if [[ "$*" == *"--format json"* ]]; then
  jq -Rs '{value: .}' < "$AUDIT_DIR/git-note"
else
  cat "$AUDIT_DIR/git-note"
fi
EOF
  chmod +x "$AUDIT_DIR/bin/op"

  run "$BATS_TEST_DIRNAME/../setup-gitconfig-from-1password.sh"

  [ "$status" -eq 0 ]
  if stat -c %a "$HOME/Developer/work/.gitconfig_include" >/dev/null 2>&1; then
    mode=$(stat -c %a "$HOME/Developer/work/.gitconfig_include")
  else
    mode=$(stat -f %Lp "$HOME/Developer/work/.gitconfig_include")
  fi
  [ "$mode" = 600 ]
  [[ "$output" != *"confidential-work@example.com"* ]]
  [[ "$output" != *"private-org.example"* ]]
}

@test "SSH installation decodes multiline and quoted 1Password fields into usable config and keys" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  ssh-keygen -q -t ed25519 -N '' -C 'test,example' -f "$AUDIT_DIR/key"
  cat > "$AUDIT_DIR/ssh-note" <<'EOF'
Host *
  IdentityAgent "~/.1password/agent.sock"
EOF
  cat > "$AUDIT_DIR/bin/op" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "account list" ]] && exit 0
source_file="$AUDIT_DIR/ssh-note"
[[ "$*" == *"--fields private key"* ]] && source_file="$AUDIT_DIR/key"
[[ "$*" == *"--fields public key"* ]] && source_file="$AUDIT_DIR/key.pub"
if [[ "$*" == *"--format json"* ]]; then
  jq -Rs '{value: .}' < "$source_file"
else
  jq -Rsr '[.] | @csv' < "$source_file"
fi
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > "$AUDIT_DIR/bin/sleep"
  chmod +x "$AUDIT_DIR/bin/op" "$AUDIT_DIR/bin/sleep"

  run "$BATS_TEST_DIRNAME/../setup-ssh-from-1password.sh" --profile personal --unsafe --yes --no-input

  [ "$status" -eq 0 ]
  run ssh-keygen -y -f "$HOME/.ssh/personal_github_authentication"
  [ "$status" -eq 0 ]
  run ssh-keygen -l -f "$HOME/.ssh/personal_github_authentication.pub"
  [ "$status" -eq 0 ]
  run ssh -G -F "$HOME/.ssh/config" example.com
  [ "$status" -eq 0 ]
  cmp "$AUDIT_DIR/key" "$HOME/.ssh/personal_github_authentication"
  cmp "$AUDIT_DIR/key.pub" "$HOME/.ssh/personal_github_authentication.pub"
}

@test "work Git config decoding preserves quoted values when OP_FORMAT is set" {
  export OP_FORMAT=json
  cat > "$AUDIT_DIR/git-note" <<'EOF'
[user]
  name = "User \"Nickname\""
EOF
  cat > "$AUDIT_DIR/bin/op" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "account list" ]] && exit 0
jq -Rs '{value: .}' < "$AUDIT_DIR/git-note"
EOF
  chmod +x "$AUDIT_DIR/bin/op"

  run "$BATS_TEST_DIRNAME/../setup-gitconfig-from-1password.sh"

  [ "$status" -eq 0 ]
  run git config --file "$HOME/Developer/work/.gitconfig_include" user.name
  [ "$status" -eq 0 ]
  [ "$output" = 'User "Nickname"' ]
}

@test "macOS show mode lists multiple applications and continues to preferences" {
  [ -d /Applications ] || skip "macOS Applications directory required"
  cat > "$AUDIT_DIR/bin/find" <<'EOF'
#!/usr/bin/env bash
printf '/Applications/First.app\n/Applications/Second.app\n'
EOF
  for command_name in sw_vers sysctl defaults brew; do
    printf '#!/usr/bin/env bash\necho mock-value\n' > "$AUDIT_DIR/bin/$command_name"
  done
  chmod +x "$AUDIT_DIR/bin/"*

  run "$BATS_TEST_DIRNAME/../_macos/macos.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 2 applications"* ]]
  [[ "$output" == *"Current System Preferences"* ]]
}

@test "macOS apply uses the supplied settings activation command" {
  command -v yq >/dev/null 2>&1 || skip "yq required"
  printf '{}\n' > "$AUDIT_DIR/config.yaml"
  printf '#!/usr/bin/env bash\ntouch "$AUDIT_DIR/activation-called"\n' > "$AUDIT_DIR/bin/activateSettings"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$AUDIT_DIR/bin/killall"
  chmod +x "$AUDIT_DIR/bin/activateSettings" "$AUDIT_DIR/bin/killall"
  export MACOS_ACTIVATE_SETTINGS_CMD="$AUDIT_DIR/bin/activateSettings"
  # Intercept the old absolute call during the red phase without touching macOS.
  cat > "$AUDIT_DIR/bash-env" <<'EOF'
function /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings() {
  touch "$AUDIT_DIR/legacy-activation-called"
}
EOF
  export BASH_ENV="$AUDIT_DIR/bash-env"

  run "$BATS_TEST_DIRNAME/../_macos/macos.sh" --no-input "$AUDIT_DIR/config.yaml"

  [ "$status" -eq 0 ]
  [ -e "$AUDIT_DIR/activation-called" ]
  [ ! -e "$AUDIT_DIR/legacy-activation-called" ]
}


@test "bootstrap skip-1password also excludes both casks from Brewfile installation" {
  cat > "$AUDIT_DIR/bin/brew" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == bundle ]]; then
  printf '%s\n' "${HOMEBREW_BUNDLE_CASK_SKIP:-}" > "$AUDIT_DIR/skipped-casks"
fi
EOF
  chmod +x "$AUDIT_DIR/bin/brew"
  export HOMEBREW_BUNDLE_CASK_SKIP=existing-cask

  run env OSTYPE=darwin "$BATS_TEST_DIRNAME/../bootstrap.sh" --skip-1password --no-input --skip-stow --skip-borders --skip-mise

  [ "$status" -eq 0 ]
  [ "$(cat "$AUDIT_DIR/skipped-casks")" = 'existing-cask 1password 1password-cli' ]
}

@test "SSH setup refuses a folded source directory before accessing 1Password" {
  mkdir -p "$AUDIT_DIR/checkout/ssh/.ssh"
  cp "$BATS_TEST_DIRNAME/../setup-ssh-from-1password.sh" "$AUDIT_DIR/checkout/"
  cp "$BATS_TEST_DIRNAME/../stow.sh" "$AUDIT_DIR/checkout/"
  ln -s "$AUDIT_DIR/checkout/ssh/.ssh" "$HOME/.ssh"
  cat > "$AUDIT_DIR/bin/op" <<'OP'
#!/usr/bin/env bash
touch "$AUDIT_DIR/password-accessed"
[[ "$1 $2" == "account list" ]] && exit 0
exit 1
OP
  chmod +x "$AUDIT_DIR/bin/op"

  run "$AUDIT_DIR/checkout/setup-ssh-from-1password.sh" --profile personal --no-input

  [ "$status" -ne 0 ]
  [ ! -e "$AUDIT_DIR/password-accessed" ]
  [ ! -d "$AUDIT_DIR/checkout/ssh/.ssh/backups" ]
  [[ "$output" == *"Refusing to write SSH material into the dotfiles checkout"* ]]
}

@test "work Git setup refuses a checkout directory before accessing 1Password" {
  mkdir -p "$AUDIT_DIR/checkout/work-config" "$HOME/Developer"
  cp "$BATS_TEST_DIRNAME/../setup-gitconfig-from-1password.sh" "$AUDIT_DIR/checkout/"
  cp "$BATS_TEST_DIRNAME/../stow.sh" "$AUDIT_DIR/checkout/"
  ln -s "$AUDIT_DIR/checkout/work-config" "$HOME/Developer/work"
  cat > "$AUDIT_DIR/bin/op" <<'OP'
#!/usr/bin/env bash
touch "$AUDIT_DIR/password-accessed"
[[ "$1 $2" == "account list" ]] && exit 0
exit 1
OP
  chmod +x "$AUDIT_DIR/bin/op"

  run "$AUDIT_DIR/checkout/setup-gitconfig-from-1password.sh"

  [ "$status" -ne 0 ]
  [ ! -e "$AUDIT_DIR/password-accessed" ]
  [ ! -d "$AUDIT_DIR/checkout/work-config/backups" ]
  [[ "$output" == *"Refusing to write private Git configuration into the dotfiles checkout"* ]]
}

@test "SSH key downloads add a missing terminal newline for field and item responses" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  ssh-keygen -q -t ed25519 -N '' -C test -f "$AUDIT_DIR/key"
  cat > "$AUDIT_DIR/bin/op" <<'OP'
#!/usr/bin/env bash
[[ "$1 $2" == "account list" ]] && exit 0
if [[ "$3" == '~/.ssh/config'* ]]; then
  jq -n '{value: "Host *\n"}'
elif [[ "$*" == *"--fields private key"* ]]; then
  [[ "$AUDIT_KEY_RESPONSE" == item ]] && exit 1
  jq -Rs '{value: rtrimstr("\n")}' < "$AUDIT_DIR/key"
elif [[ "$*" == *"--fields public key"* ]]; then
  jq -Rs '{value: .}' < "$AUDIT_DIR/key.pub"
else
  jq -Rs '{fields: [{id: "private_key", value: rtrimstr("\n")}]}' < "$AUDIT_DIR/key"
fi
OP
  printf '#!/usr/bin/env bash\nexit 0\n' > "$AUDIT_DIR/bin/sleep"
  chmod +x "$AUDIT_DIR/bin/op" "$AUDIT_DIR/bin/sleep"

  for response_mode in field item; do
    export AUDIT_KEY_RESPONSE="$response_mode"
    run "$BATS_TEST_DIRNAME/../setup-ssh-from-1password.sh" --profile personal --unsafe --yes --no-input --force
    [ "$status" -eq 0 ]
    run ssh-keygen -y -f "$HOME/.ssh/personal_github_authentication"
    [ "$status" -eq 0 ]
    cmp "$AUDIT_DIR/key" "$HOME/.ssh/personal_github_authentication"
  done
}

@test "fresh SSH Stow and setup retain example fallback without exposing the source tree" {
  command -v stow >/dev/null 2>&1 || skip "GNU Stow required"
  command -v jq >/dev/null 2>&1 || skip "jq required"
  mkdir -p "$AUDIT_DIR/checkout/ssh/.ssh/config.d"
  cp "$BATS_TEST_DIRNAME/../stow.sh" "$BATS_TEST_DIRNAME/../setup-ssh-from-1password.sh" "$AUDIT_DIR/checkout/"
  cp "$BATS_TEST_DIRNAME/../ssh/.stow-local-ignore" "$AUDIT_DIR/checkout/ssh/"
  cp "$BATS_TEST_DIRNAME/../ssh/.ssh/config.example" "$AUDIT_DIR/checkout/ssh/.ssh/"
  cp "$BATS_TEST_DIRNAME/../ssh/.ssh/config.d/personal.conf.example" "$AUDIT_DIR/checkout/ssh/.ssh/config.d/"
  ssh-keygen -q -t ed25519 -N '' -C test -f "$AUDIT_DIR/key"
  cat > "$AUDIT_DIR/bin/op" <<'OP'
#!/usr/bin/env bash
[[ "$1 $2" == "account list" ]] && exit 0
if [[ "$*" == *"--fields public key"* ]]; then
  jq -Rs '{value: .}' < "$AUDIT_DIR/key.pub"
else
  exit 1
fi
OP
  chmod +x "$AUDIT_DIR/bin/op"

  run "$AUDIT_DIR/checkout/stow.sh" ssh
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.ssh/config.example" ]

  run "$AUDIT_DIR/checkout/setup-ssh-from-1password.sh" --profile personal --no-input
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.ssh" ]
  cmp "$AUDIT_DIR/checkout/ssh/.ssh/config.example" "$HOME/.ssh/config"
  cmp "$AUDIT_DIR/checkout/ssh/.ssh/config.d/personal.conf.example" "$HOME/.ssh/config.d/personal.conf"
  [ ! -e "$AUDIT_DIR/checkout/ssh/.ssh/config" ]
  run ssh -G -F "$HOME/.ssh/config" github.com
  [ "$status" -eq 0 ]
}
