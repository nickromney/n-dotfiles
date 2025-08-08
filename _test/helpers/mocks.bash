#!/usr/bin/env bash
# Test helper functions for mocking commands

# Directory to store mock commands
export MOCK_BIN_DIR="$BATS_TEST_TMPDIR/mock_bin"

# Setup mock environment
setup_mocks() {
  mkdir -p "$MOCK_BIN_DIR"
  export PATH="$MOCK_BIN_DIR:$PATH"
  
  # Create a directory for mock outputs
  export MOCK_OUTPUT_DIR="$BATS_TEST_TMPDIR/mock_output"
  mkdir -p "$MOCK_OUTPUT_DIR"
  
  # Create a directory for recording mock calls
  export MOCK_CALLS_DIR="$BATS_TEST_TMPDIR/mock_calls"
  mkdir -p "$MOCK_CALLS_DIR"
}

# Create a mock command that records its calls
mock_command() {
  local cmd="$1"
  local exit_code="${2:-0}"
  local output="${3:-}"
  
  cat > "$MOCK_BIN_DIR/$cmd" << EOF
#!/usr/bin/env bash
# Record the call
echo "\$@" >> "$MOCK_CALLS_DIR/$cmd.calls"

# Output if provided
if [[ -n "$output" ]]; then
  echo "$output"
fi

# Check for special behaviors based on arguments
case "\$*" in
  *--version*)
    echo "$cmd version 1.0.0-mock"
    exit 0
    ;;
  *-v*)
    echo "$cmd 1.0.0-mock"
    exit 0
    ;;
esac

exit $exit_code
EOF
  chmod +x "$MOCK_BIN_DIR/$cmd"
}

# Create a mock command with custom behavior
mock_command_with_script() {
  local cmd="$1"
  local script="$2"
  
  cat > "$MOCK_BIN_DIR/$cmd" << EOF
#!/usr/bin/env bash
# Record the call
echo "\$@" >> "$MOCK_CALLS_DIR/$cmd.calls"

# Custom behavior
$script
EOF
  chmod +x "$MOCK_BIN_DIR/$cmd"
}

# Check if a mock command was called
assert_mock_called() {
  local cmd="$1"
  local expected_args="${2:-}"
  
  if [[ ! -f "$MOCK_CALLS_DIR/$cmd.calls" ]]; then
    echo "Mock command '$cmd' was not called" >&2
    return 1
  fi
  
  if [[ -n "$expected_args" ]]; then
    if ! grep -qF -- "$expected_args" "$MOCK_CALLS_DIR/$cmd.calls"; then
      echo "Mock command '$cmd' was not called with expected args: $expected_args" >&2
      echo "Actual calls:" >&2
      cat "$MOCK_CALLS_DIR/$cmd.calls" >&2
      return 1
    fi
  fi
  
  return 0
}

# Check if a mock command was NOT called
assert_mock_not_called() {
  local cmd="$1"
  
  if [[ -f "$MOCK_CALLS_DIR/$cmd.calls" ]]; then
    echo "Mock command '$cmd' was called but should not have been" >&2
    echo "Calls:" >&2
    cat "$MOCK_CALLS_DIR/$cmd.calls" >&2
    return 1
  fi
  
  return 0
}

# Get the number of times a mock was called
get_mock_call_count() {
  local cmd="$1"
  
  if [[ ! -f "$MOCK_CALLS_DIR/$cmd.calls" ]]; then
    echo "0"
  else
    wc -l < "$MOCK_CALLS_DIR/$cmd.calls"
  fi
}

# Clear mock calls for a command
clear_mock_calls() {
  local cmd="$1"
  rm -f "$MOCK_CALLS_DIR/$cmd.calls"
}

# Mock specific package managers
mock_brew() {
  # shellcheck disable=SC2016  # Single quotes prevent variable expansion in script
  mock_command_with_script "brew" '
case "$1" in
  install)
    shift
    if [[ "$1" == "--cask" ]]; then
      shift
      echo "==> Installing cask $@"
    else
      echo "==> Installing $@"
    fi
    exit 0
    ;;
  tap)
    shift
    echo "==> Tapping $@"
    exit 0
    ;;
  --version)
    echo "Homebrew 4.0.0"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'
}

mock_apt_get() {
  # shellcheck disable=SC2016  # Single quotes prevent variable expansion in script
  mock_command_with_script "apt-get" '
case "$1" in
  update)
    echo "Hit:1 http://archive.ubuntu.com/ubuntu focal InRelease"
    exit 0
    ;;
  install)
    shift
    [[ "$1" == "-y" ]] && shift
    echo "Reading package lists... Done"
    echo "Building dependency tree... Done"
    echo "The following NEW packages will be installed:"
    echo "  $@"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'
}

mock_arkade() {
  # shellcheck disable=SC2016  # Single quotes prevent variable expansion in script
  mock_command_with_script "arkade" '
case "$1" in
  get)
    shift
    echo "Downloading $1"
    exit 0
    ;;
  system)
    shift
    [[ "$1" == "install" ]] && shift
    echo "Installing system app: $1"
    exit 0
    ;;
  install)
    shift
    echo "Installing app: $1"
    exit 0
    ;;
  version)
    echo "arkade version 0.10.0"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'
}

mock_cargo() {
  # shellcheck disable=SC2016  # Single quotes prevent variable expansion in script
  mock_command_with_script "cargo" '
case "$1" in
  install)
    shift
    if [[ "$1" == "--git" ]]; then
      shift
      url="$1"
      shift
      echo "Installing from git: $url $@"
    else
      echo "Installing $@"
    fi
    exit 0
    ;;
  --version)
    echo "cargo 1.70.0"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'
}

mock_uv() {
  # shellcheck disable=SC2016  # Single quotes prevent variable expansion in script
  mock_command_with_script "uv" '
case "$1" in
  tool)
    shift
    [[ "$1" == "install" ]] && shift
    echo "Installing Python tool: $@"
    exit 0
    ;;
  --version)
    echo "uv 0.1.0"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'
}

mock_mas() {
  # shellcheck disable=SC2016  # Single quotes prevent variable expansion in script
  mock_command_with_script "mas" '
case "$1" in
  install)
    shift
    echo "==> Downloading and installing app ID: $@"
    exit 0
    ;;
  list)
    echo "904280696   Things                 (3.21.14)"
    echo "967805235    Paste                  (5.0.9)"
    exit 0
    ;;
  outdated)
    # Return empty - nothing outdated
    exit 0
    ;;
  upgrade)
    shift
    echo "==> Upgrading app ID: $@"
    exit 0
    ;;
  version)
    echo "1.8.6"
    exit 0
    ;;
  --version)
    echo "mas version 1.8.6"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'
}

mock_stow() {
  # shellcheck disable=SC2016  # Single quotes prevent variable expansion in script
  mock_command_with_script "stow" '
# Parse options
while [[ "$1" =~ ^- ]]; do
  case "$1" in
    --dir=*)
      dir="${1#--dir=}"
      shift
      ;;
    --target=*)
      target="${1#--target=}"
      shift
      ;;
    --adopt)
      adopt=1
      shift
      ;;
    --no)
      dry_run=1
      shift
      ;;
    --verbose=*)
      verbose="${1#--verbose=}"
      shift
      ;;
    -R)
      restow=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Remaining args are packages
for pkg in "$@"; do
  if [[ -n "$dry_run" ]]; then
    echo "WOULD STOW: $pkg"
  else
    echo "STOWING: $pkg"
  fi
done

exit 0
'
}

# Mock yq with test data
mock_yq() {
  # shellcheck disable=SC2034  # tools_yaml reserved for future use
  local tools_yaml="${1:-$BATS_TEST_DIRNAME/fixtures/tools.yaml}"
  
  mock_command_with_script "yq" "
case \"\$*\" in
  \".tools | keys | .[]\"*)
    # Return actual tools from fixtures plus test tools
    echo \"jq\"
    echo \"docker\"
    echo \"homebrew/cask-fonts\"
    echo \"kubectl\"
    echo \"prometheus\"
    echo \"openfaas\"
    echo \"ripgrep\"
    echo \"zoxide\"
    echo \"ruff\"
    echo \"curl\"
    echo \"special-tool\"
    echo \"tool1\"
    echo \"tool2\"
    echo \"tool3\"
    exit 0
    ;;
  \".tools[].manager\"*)
    # Return unique managers
    echo \"brew\"
    echo \"brew\"
    echo \"brew\"
    echo \"arkade\"
    echo \"arkade\"
    echo \"arkade\"
    echo \"cargo\"
    echo \"cargo\"
    echo \"uv\"
    echo \"apt\"
    echo \"brew\"
    exit 0
    ;;
  \".tools.jq.manager\"*)
    echo \"brew\"
    exit 0
    ;;
  \".tools.jq.type\"*)
    echo \"package\"
    exit 0
    ;;
  \".tools.jq.check_command\"*)
    echo \"jq --version\"
    exit 0
    ;;
  \".tools.jq.install_args[]\"*)
    exit 0
    ;;
  \".tools.docker.manager\"*)
    echo \"brew\"
    exit 0
    ;;
  \".tools.docker.type\"*)
    echo \"cask\"
    exit 0
    ;;
  \".tools.docker.check_command\"*)
    echo \"docker --version\"
    exit 0
    ;;
  \".tools.docker.install_args[]\"*)
    exit 0
    ;;
  \".tools.\\\"homebrew/cask-fonts\\\".manager\"*|\".tools.homebrew/cask-fonts.manager\"*)
    echo \"brew\"
    exit 0
    ;;
  \".tools.\\\"homebrew/cask-fonts\\\".type\"*|\".tools.homebrew/cask-fonts.type\"*)
    echo \"tap\"
    exit 0
    ;;
  \".tools.\\\"homebrew/cask-fonts\\\".check_command\"*|\".tools.homebrew/cask-fonts.check_command\"*)
    echo \"brew tap | grep -q 'homebrew/cask-fonts'\"
    exit 0
    ;;
  \".tools.\\\"homebrew/cask-fonts\\\".install_args[]\"*|\".tools.homebrew/cask-fonts.install_args[]\"*)
    exit 0
    ;;
  \".tools.kubectl.manager\"*)
    echo \"arkade\"
    exit 0
    ;;
  \".tools.kubectl.type\"*)
    echo \"get\"
    exit 0
    ;;
  \".tools.kubectl.check_command\"*)
    echo \"kubectl version --client\"
    exit 0
    ;;
  \".tools.kubectl.install_args[]\"*)
    exit 0
    ;;
  \".tools.prometheus.manager\"*)
    echo \"arkade\"
    exit 0
    ;;
  \".tools.prometheus.type\"*)
    echo \"system\"
    exit 0
    ;;
  \".tools.prometheus.check_command\"*)
    echo \"prometheus --version\"
    exit 0
    ;;
  \".tools.prometheus.install_args[]\"*)
    exit 0
    ;;
  \".tools.openfaas.manager\"*)
    echo \"arkade\"
    exit 0
    ;;
  \".tools.openfaas.type\"*)
    echo \"install\"
    exit 0
    ;;
  \".tools.openfaas.check_command\"*)
    echo \"arkade info openfaas\"
    exit 0
    ;;
  \".tools.openfaas.install_args[]\"*)
    echo \"--namespace\"
    echo \"openfaas\"
    exit 0
    ;;
  \".tools.ripgrep.manager\"*)
    echo \"cargo\"
    exit 0
    ;;
  \".tools.ripgrep.type\"*)
    echo \"binary\"
    exit 0
    ;;
  \".tools.ripgrep.check_command\"*)
    echo \"rg --version\"
    exit 0
    ;;
  \".tools.ripgrep.install_args[]\"*)
    exit 0
    ;;
  \".tools.zoxide.manager\"*)
    echo \"cargo\"
    exit 0
    ;;
  \".tools.zoxide.type\"*)
    echo \"git\"
    exit 0
    ;;
  \".tools.zoxide.check_command\"*)
    echo \"zoxide --version\"
    exit 0
    ;;
  \".tools.zoxide.install_args[]\"*)
    echo \"https://github.com/ajeetdsouza/zoxide\"
    exit 0
    ;;
  \".tools.ruff.manager\"*)
    echo \"uv\"
    exit 0
    ;;
  \".tools.ruff.type\"*)
    echo \"tool\"
    exit 0
    ;;
  \".tools.ruff.check_command\"*)
    echo \"ruff --version\"
    exit 0
    ;;
  \".tools.ruff.install_args[]\"*)
    exit 0
    ;;
  \".tools.curl.manager\"*)
    echo \"apt\"
    exit 0
    ;;
  \".tools.curl.type\"*)
    echo \"package\"
    exit 0
    ;;
  \".tools.curl.check_command\"*)
    echo \"curl --version\"
    exit 0
    ;;
  \".tools.curl.install_args[]\"*)
    exit 0
    ;;
  \".tools.special-tool.manager\"*)
    echo \"brew\"
    exit 0
    ;;
  \".tools.special-tool.type\"*)
    echo \"package\"
    exit 0
    ;;
  \".tools.special-tool.check_command\"*)
    echo \"null\"
    exit 0
    ;;
  \".tools.special-tool.install_args[]\"*)
    echo \"--with-feature\"
    exit 0
    ;;
  \".tools.tool1.manager\"*)
    echo \"brew\"
    exit 0
    ;;
  \".tools.tool1.type\"*)
    echo \"package\"
    exit 0
    ;;
  \".tools.tool1.check_command\"*)
    echo \"tool1 --version\"
    exit 0
    ;;
  \".tools.tool1.install_args[]\"*)
    exit 0
    ;;
  \".tools.tool2.manager\"*)
    echo \"arkade\"
    exit 0
    ;;
  \".tools.tool2.type\"*)
    echo \"get\"
    exit 0
    ;;
  \".tools.tool2.check_command\"*)
    echo \"tool2 version\"
    exit 0
    ;;
  \".tools.tool2.install_args[]\"*)
    exit 0
    ;;
  \".tools.tool3.manager\"*)
    echo \"cargo\"
    exit 0
    ;;
  \".tools.tool3.type\"*)
    echo \"binary\"
    exit 0
    ;;
  \".tools.tool3.check_command\"*)
    echo \"tool3 --version\"
    exit 0
    ;;
  \".tools.tool3.install_args[]\"*)
    exit 0
    ;;
  *)
    echo \"null\"
    exit 0
    ;;
esac
"
}

# Mock id command for root checking
mock_id() {
  local uid="${1:-1000}"
  mock_command_with_script "id" "
# shellcheck disable=SC2016  # Single quotes prevent variable expansion
case \"\$1\" in
  -u)
    echo \"$uid\"
    exit 0
    ;;
  *)
    echo \"uid=$uid(testuser) gid=1000(testuser) groups=1000(testuser)\"
    exit 0
    ;;
esac
"
}

# Mock command_exists function
mock_command_exists() {
  local commands=("$@")
  
  # Build case patterns
  local case_patterns=""
  for cmd in "${commands[@]}"; do
    if [[ -z "$case_patterns" ]]; then
      case_patterns="$cmd"
    else
      case_patterns="$case_patterns|$cmd"
    fi
  done
  
  # Override the command_exists function
  # shellcheck disable=SC2016  # Single quotes prevent variable expansion
  eval "command_exists() {
    local cmd=\"\$1\"
    case \"\$cmd\" in
      $case_patterns) return 0 ;;
      *) return 1 ;;
    esac
  }"
}

# Cleanup function
teardown_mocks() {
  # Remove mock binaries from PATH
  export PATH="${PATH#"$MOCK_BIN_DIR:"}"
  
  # Clean up temporary directories
  rm -rf "$MOCK_BIN_DIR" "$MOCK_OUTPUT_DIR" "$MOCK_CALLS_DIR"
}