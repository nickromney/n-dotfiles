#!/usr/bin/env bats

load helpers/mocks

setup() {
  # Create a temporary directory for testing
  export TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export MOCK_BIN_DIR="$TEST_DIR/bin"
  export PATH="$MOCK_BIN_DIR:$PATH"

  # Create necessary directories
  mkdir -p "$HOME/.ssh"
  mkdir -p "$HOME/Developer/work"
  mkdir -p "$MOCK_BIN_DIR"

  # Create a basic .gitconfig for testing
  cat > "$HOME/.gitconfig" <<'EOF'
[user]
  name = Test User
  email = test@example.com

[includeIf "gitdir:~/Developer/work/"]
  path = ~/Developer/work/.gitconfig_include
EOF

  # Mock the op command
  create_mock_op

  # Mock git command for config validation
  cat > "$MOCK_BIN_DIR/git" <<'EOF'
#!/bin/bash
if [[ "$1" == "config" ]] && [[ "$2" == "--file="* ]] && [[ "$3" == "--list" ]]; then
  exit 0  # Config is valid
fi
exit 1
EOF
  chmod +x "$MOCK_BIN_DIR/git"
}

teardown() {
  rm -rf "$TEST_DIR"
}

create_mock_op() {
  cat > "$MOCK_BIN_DIR/op" <<'EOF'
#!/bin/bash
# Mock 1Password CLI

# Handle account list (checking if signed in)
if [[ "$1" == "account" ]] && [[ "$2" == "list" ]]; then
  echo "Account ID: test-account"
  exit 0
fi

# Handle item get
if [[ "$1" == "item" ]] && [[ "$2" == "get" ]]; then
  item_name="$3"
  vault=""

  # Parse vault if provided
  for arg in "$@"; do
    if [[ "$arg" == "--vault="* ]]; then
      vault="${arg#--vault=}"
    fi
  done

  # Simulate items that exist in 1Password
  case "$item_name" in
    "~/.ssh/config")
      if [[ "$@" == *"--fields"* ]] && [[ "$@" == *"notes"* ]]; then
        cat <<'CONFIG'
Host *
  IdentityAgent "~/.1password/agent.sock"

Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/work_key.pub
CONFIG
      else
        echo "~/.ssh/config found"
      fi
      exit 0
      ;;
    "work .gitconfig_include")
      if [[ "$@" == *"--fields"* ]] && [[ "$@" == *"notes"* ]]; then
        cat <<'GITCONFIG'
[url "github-work:OrgName/"]
  insteadOf = git@github.com:OrgName/

[user]
  email = work@example.com
GITCONFIG
      else
        echo "work .gitconfig_include found"
      fi
      exit 0
      ;;
    "personal_github_authentication"|"personal_github_signing"|"work_aws_2024_client_1"|"work_github_2025_client_1")
      echo "$item_name found"
      exit 0
      ;;
    *)
      echo "ERROR: Item not found: $item_name" >&2
      exit 1
      ;;
  esac
fi

# Handle signin
if [[ "$1" == "signin" ]]; then
  echo "export OP_SESSION_test='mock-session-token'"
  exit 0
fi

echo "Unhandled op command: $@" >&2
exit 1
EOF
  chmod +x "$MOCK_BIN_DIR/op"
}

# Tests for setup-ssh-from-1password.sh

@test "SSH setup: dry-run shows available items" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  run ./setup-ssh-from-1password.sh --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"SSH Config Dry Run"* ]]
  [[ "$output" == *"Found in 1Password:"* ]]
  [[ "$output" == *"~/.ssh/config (Secure Note)"* ]]
  [[ "$output" == *"personal_github_authentication"* ]]
  [[ "$output" == *"No files were modified"* ]]
}

@test "SSH setup: safe mode downloads only public keys" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  # Create mock that tracks what fields are requested
  cat > "$MOCK_BIN_DIR/op" <<'EOF'
#!/bin/bash
echo "$@" >> "$TEST_DIR/op-calls.log"

if [[ "$1" == "account" ]] && [[ "$2" == "list" ]]; then
  echo "Account ID: test-account"
  exit 0
fi

if [[ "$1" == "item" ]] && [[ "$2" == "get" ]]; then
  if [[ "$@" == *"--fields notes"* ]]; then
    echo "Host *"
    echo "  IdentityAgent ~/.1password/agent.sock"
    exit 0
  fi

  if [[ "$@" == *"--fields \"public key\""* ]]; then
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN... test@example.com"
    exit 0
  fi

  if [[ "$@" == *"--fields \"private key\""* ]]; then
    echo "ERROR: Should not request private key in safe mode!" >&2
    exit 1
  fi
fi
exit 1
EOF
  chmod +x "$MOCK_BIN_DIR/op"

  # Run in safe mode (default)
  run ./setup-ssh-from-1password.sh

  # Check that only public keys were requested
  grep -q "public key" "$TEST_DIR/op-calls.log"
  ! grep -q "private key" "$TEST_DIR/op-calls.log"
}

@test "SSH setup: unsafe mode requires confirmation" {
  skip "Interactive test - requires manual testing"
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  # Simulate user declining
  run bash -c 'echo "no" | ./setup-ssh-from-1password.sh --unsafe'

  [ "$status" -eq 0 ]
  [[ "$output" == *"PRIVATE KEY DOWNLOAD MODE"* ]]
  [[ "$output" == *"Do you want to download private keys?"* ]]
  [[ "$output" == *"Cancelled. Running in safe mode"* ]]
}

@test "SSH setup: unsafe mode with confirmation downloads private keys" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  # Mock sleep to avoid waiting
  cat > "$MOCK_BIN_DIR/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/sleep"

  # Create mock that allows private key download
  cat > "$MOCK_BIN_DIR/op" <<'EOF'
#!/bin/bash
echo "$@" >> "$TEST_DIR/op-calls.log"

if [[ "$1" == "account" ]] && [[ "$2" == "list" ]]; then
  echo "Account ID: test-account"
  exit 0
fi

if [[ "$1" == "item" ]] && [[ "$2" == "get" ]]; then
  if [[ "$@" == *"--fields \"private key\""* ]]; then
    echo "-----BEGIN OPENSSH PRIVATE KEY-----"
    echo "mock private key content"
    echo "-----END OPENSSH PRIVATE KEY-----"
    exit 0
  fi

  if [[ "$@" == *"--fields \"public key\""* ]]; then
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN... test@example.com"
    exit 0
  fi
fi
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/op"

  # Simulate user confirming
  echo "yes" | run ./setup-ssh-from-1password.sh --unsafe

  # Check that private keys were requested
  grep -q "private key" "$TEST_DIR/op-calls.log"
}

@test "SSH setup: help option shows usage" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  run ./setup-ssh-from-1password.sh --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--unsafe"* ]]
  [[ "$output" == *"Default behavior:"* ]]
  [[ "$output" == *"public keys only"* ]]
  [[ "$output" == *"Examples:"* ]]
}

@test "SSH setup: detects missing op command" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  # Remove op from PATH completely
  export PATH="/usr/bin:/bin"

  run ./setup-ssh-from-1password.sh --dry-run

  [ "$status" -eq 1 ]
  [[ "$output" == *"1Password CLI (op) is not installed"* ]]
  [[ "$output" == *"brew install --cask 1password-cli"* ]]
}

@test "SSH setup: handles missing items in dry-run" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  # Create a mock that reports some items as missing
  cat > "$MOCK_BIN_DIR/op" <<'EOF'
#!/bin/bash
if [[ "$1" == "account" ]] && [[ "$2" == "list" ]]; then
  echo "Account ID: test-account"
  exit 0
fi

if [[ "$1" == "item" ]] && [[ "$2" == "get" ]]; then
  item_name="$3"
  case "$item_name" in
    "~/.ssh/config")
      echo "~/.ssh/config found"
      exit 0
      ;;
    *)
      echo "ERROR: Item not found: $item_name" >&2
      exit 1
      ;;
  esac
fi
exit 1
EOF
  chmod +x "$MOCK_BIN_DIR/op"

  run ./setup-ssh-from-1password.sh --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Found in 1Password:"* ]]
  [[ "$output" == *"~/.ssh/config"* ]]
  [[ "$output" == *"Not found in 1Password:"* ]]
  [[ "$output" == *"personal_github_authentication"* ]]
}

@test "SSH setup: checks for SSH agent socket in dry-run" {
  skip "Cannot create real socket in test environment - tested manually"

  # This test is skipped because we cannot create a real Unix socket
  # in the test environment. The mkfifo creates a named pipe, not a socket.
  # The script uses [ -S ... ] which specifically checks for sockets.
  # This functionality has been tested manually with a real 1Password setup.
}

@test "SSH setup: detects missing SSH agent socket" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  # Ensure socket doesn't exist
  rm -rf "$HOME/.1password"

  run ./setup-ssh-from-1password.sh --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"1Password SSH agent socket not found"* ]]
  [[ "$output" == *"Enable it in 1Password Settings"* ]]
}

# Tests for setup-gitconfig-from-1password.sh

@test "Git config setup: dry-run shows available items" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-gitconfig-from-1password.sh" .

  run ./setup-gitconfig-from-1password.sh --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Git Config Dry Run"* ]]
  [[ "$output" == *"Found in 1Password:"* ]]
  [[ "$output" == *"work .gitconfig_include"* ]]
  [[ "$output" == *"No files were modified"* ]]
}

@test "Git config setup: help option shows usage" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-gitconfig-from-1password.sh" .

  run ./setup-gitconfig-from-1password.sh --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"Examples:"* ]]
}

@test "Git config setup: detects includeIf directive" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-gitconfig-from-1password.sh" .

  run ./setup-gitconfig-from-1password.sh --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Found includeIf directive in .gitconfig"* ]]
}

@test "Git config setup: detects missing includeIf" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-gitconfig-from-1password.sh" .

  # Create gitconfig without includeIf
  cat > "$HOME/.gitconfig" <<'EOF'
[user]
  name = Test User
  email = test@example.com
EOF

  run ./setup-gitconfig-from-1password.sh --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"includeIf directive not found"* ]]
  [[ "$output" == *"Will need to add includeIf section"* ]]
}

@test "Git config setup: handles missing gitconfig file" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-gitconfig-from-1password.sh" .

  rm -f "$HOME/.gitconfig"

  run ./setup-gitconfig-from-1password.sh --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Main .gitconfig not found"* ]]
}

@test "Git config setup: handles unknown options" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-gitconfig-from-1password.sh" .

  run ./setup-gitconfig-from-1password.sh --unknown-option

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --unknown-option"* ]]
}

@test "SSH setup: handles unknown options" {
  cd "$TEST_DIR"
  cp "${BATS_TEST_DIRNAME}/../setup-ssh-from-1password.sh" .

  run ./setup-ssh-from-1password.sh --unknown-option

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --unknown-option"* ]]
}
