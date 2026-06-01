#!/usr/bin/env bats

load helpers/mocks

setup() {
  setup_mocks

  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export INSTALL_REPO_ROOT="$REPO_ROOT"
  export CONFIG_DIR="_configs"
  export CONFIG_FILES=("test")
  export DRY_RUN="false"
  export VERBOSE="false"
  export STOW="false"
  export FORCE="false"
  export UPDATE="false"
  export LIST_MODE="false"
  export CONFIG_FILES_SET_VIA_CLI="false"
  export CONFIG_FILES_SET_VIA_ENV="true"

  cd "$REPO_ROOT" || return 1

  set +e
  # shellcheck source=/dev/null
  source ./install.sh --source-only
  set -e
}

teardown() {
  teardown_mocks
}

write_manifest_bundle() {
  local target_dir=$1
  local brewfile_content=$2
  local arkade_content=$3
  local metadata_content=$4

  mkdir -p "$target_dir"
  printf '%s\n' "$brewfile_content" > "$target_dir/Brewfile"
  printf '%s\n' "$arkade_content" > "$target_dir/arkade.tsv"
  printf '%s\n' "$metadata_content" > "$target_dir/metadata.json"
}

create_manifest_generator() {
  local source_dir=$1
  export MOCK_MANIFEST_SOURCE="$source_dir"
  export MANIFEST_GENERATOR="$BATS_TEST_TMPDIR/mock-generate-install-manifests.sh"

  cat > "$MANIFEST_GENERATOR" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output_dir=$1
shift

mkdir -p "$output_dir"
cp "$MOCK_MANIFEST_SOURCE/Brewfile" "$output_dir/Brewfile"
cp "$MOCK_MANIFEST_SOURCE/arkade.tsv" "$output_dir/arkade.tsv"
cp "$MOCK_MANIFEST_SOURCE/metadata.json" "$output_dir/metadata.json"
EOF
  chmod +x "$MANIFEST_GENERATOR"
}

@test "command_exists returns success for an available command" {
  mock_command "demo-cmd"

  run command_exists "demo-cmd"
  [ "$status" -eq 0 ]
}

@test "check_requirements fails when yq is missing" {
  command_exists() {
    [[ "$1" == "which" ]]
  }
  export -f command_exists

  run check_requirements
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required commands: yq"* ]]
}

@test "prepare_config_files resolves repo-relative configs" {
  mkdir -p "$BATS_TEST_TMPDIR/_configs"
  touch "$BATS_TEST_TMPDIR/_configs/test.yaml"
  export CONFIG_DIR="$BATS_TEST_TMPDIR/_configs"
  export CONFIG_FILES=("test")

  prepare_config_files
  [ "${RESOLVED_CONFIG_FILES[0]}" = "$BATS_TEST_TMPDIR/_configs/test.yaml" ]
}

@test "collect_catalog_config_files walks the config tree when no config was explicitly selected" {
  mkdir -p "$BATS_TEST_TMPDIR/_configs/focus" "$BATS_TEST_TMPDIR/_configs/host"
  touch "$BATS_TEST_TMPDIR/_configs/focus/demo.yaml"
  touch "$BATS_TEST_TMPDIR/_configs/host/common.yml"
  export CONFIG_DIR="$BATS_TEST_TMPDIR/_configs"
  export CONFIG_FILES=("host/common")
  export CONFIG_FILES_SET_VIA_CLI="false"
  export CONFIG_FILES_SET_VIA_ENV="false"

  run collect_catalog_config_files
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/_configs/focus/demo.yaml"* ]]
  [[ "$output" == *"$BATS_TEST_TMPDIR/_configs/host/common.yml"* ]]
}

@test "print_available_tool_catalog emits tab-separated inventory rows" {
  mkdir -p "$BATS_TEST_TMPDIR/_configs/focus" "$BATS_TEST_TMPDIR/_configs/host"
  cat >"$BATS_TEST_TMPDIR/_configs/focus/demo.yaml" <<'EOF'
tools:
  jq:
    manager: brew
    type: package
    description: "JSON processor"
    documentation_url: "https://jqlang.org/"
    category: data
  docker-desktop:
    manager: manual
    type: check
    description: "Docker Desktop"
    documentation_url: "https://www.docker.com/"
    category: containers
    skip_update: true
EOF
  cat >"$BATS_TEST_TMPDIR/_configs/host/common.yaml" <<'EOF'
tools:
  uv:
    manager: brew
    type: package
    description: "Python installer"
    documentation_url: "https://docs.astral.sh/uv/"
    category: python
EOF
  export CONFIG_DIR="$BATS_TEST_TMPDIR/_configs"
  export CONFIG_FILES=("host/common")
  export CONFIG_FILES_SET_VIA_CLI="false"
  export CONFIG_FILES_SET_VIA_ENV="false"

  run print_available_tool_catalog
  [ "$status" -eq 0 ]
  [[ "$output" == $'config\ttool\tmanager\ttype\tcategory\tauto_install\tupdatable\tdescription\tdocumentation_url'* ]]
  [[ "$output" == *$'focus/demo\tdocker-desktop\tmanual\tcheck\tcontainers\tno\tno\tDocker Desktop\thttps://www.docker.com/'* ]]
  [[ "$output" == *$'focus/demo\tjq\tbrew\tpackage\tdata\tyes\tyes\tJSON processor\thttps://jqlang.org/'* ]]
  [[ "$output" == *$'host/common\tuv\tbrew\tpackage\tpython\tyes\tyes\tPython installer\thttps://docs.astral.sh/uv/'* ]]
}

@test "install.sh help exits successfully and documents list mode" {
  run "$REPO_ROOT/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--list"* ]]
  [[ "$output" == *"$REPO_ROOT/install.sh --list"* ]]
  [[ "$output" == *"--update            Update tools already installed from selected configs; missing tools are skipped"* ]]
  [[ "$output" == *"BREW_REFRESH=true"* ]]
}

@test "install.sh rejects list mode with update" {
  run "$REPO_ROOT/install.sh" --list --update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: --list cannot be combined with --stow, --update, or --force"* ]]
}

@test "generate_manifests calls wrapper and sets manifest paths" {
  local manifest_source="$BATS_TEST_TMPDIR/manifests"
  write_manifest_bundle "$manifest_source" \
'tap "example/tap"' \
$'kubectl\t--version 1.31.0' \
'[]'
  create_manifest_generator "$manifest_source"
  RESOLVED_CONFIG_FILES=("dummy.yaml")

  generate_manifests
  [ -f "$MANIFEST_BREWFILE" ]
  [ -f "$MANIFEST_ARKADE" ]
  [ -f "$MANIFEST_METADATA" ]
}

@test "generate_manifests writes manifests even when install is in dry-run mode" {
  local manifest_source="$BATS_TEST_TMPDIR/manifests"
  write_manifest_bundle "$manifest_source" \
'tap "example/tap"' \
$'kubectl\t--version 1.31.0' \
'[]'
  create_manifest_generator "$manifest_source"
  RESOLVED_CONFIG_FILES=("dummy.yaml")
  export DRY_RUN="true"

  generate_manifests
  [ -f "$MANIFEST_BREWFILE" ]
  [ -f "$MANIFEST_ARKADE" ]
  [ -f "$MANIFEST_METADATA" ]
}

@test "get_available_managers reads generated metadata manifests" {
  local metadata_file="$BATS_TEST_TMPDIR/metadata.json"
  cat > "$metadata_file" <<'EOF'
[
  {"tool":"jq","manager":"brew","type":"package","check_command":"jq --version","install_args":[],"skip_update":false,"apt_package":null,"dependencies":[],"extension_id":null,"app_id":null,"description":null,"documentation_url":null,"category":"data"},
  {"tool":"manual-tool","manager":"manual","type":"check","check_command":"manual-tool --version","install_args":[],"skip_update":false,"apt_package":null,"dependencies":[],"extension_id":null,"app_id":null,"description":null,"documentation_url":null,"category":"manual"}
]
EOF
  mock_command "brew"

  run get_available_managers "$metadata_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew"* ]]
  [[ "$output" == *"manual"* ]]
}

@test "load_metadata_manifest and is_tool_installed use generated metadata" {
  MANIFEST_METADATA="$BATS_TEST_TMPDIR/metadata.json"
  cat > "$MANIFEST_METADATA" <<'EOF'
[
  {"tool":"tool1","manager":"brew","type":"package","check_command":"tool1 --version","install_args":[],"skip_update":false,"apt_package":null,"dependencies":[],"extension_id":null,"app_id":null,"description":null,"documentation_url":null,"category":"test"}
]
EOF
  mock_command "tool1"

  run is_tool_installed "tool1" "$MANIFEST_METADATA"
  [ "$status" -eq 0 ]
}

@test "check_dependencies uses dependency records from metadata" {
  MANIFEST_METADATA="$BATS_TEST_TMPDIR/metadata.json"
  cat > "$MANIFEST_METADATA" <<'EOF'
[
  {
    "tool":"podman",
    "manager":"brew",
    "type":"package",
    "check_command":"podman --version",
    "install_args":[],
    "skip_update":false,
    "apt_package":null,
    "dependencies":[{"name":"krunkit","check_command":"command -v krunkit"}],
    "extension_id":null,
    "app_id":null,
    "description":null,
    "documentation_url":null,
    "category":"containers"
  }
]
EOF
  load_metadata_manifest

  set +e
  output=$(check_dependencies "podman" 2>&1)
  status=$?
  set -e

  [ "$status" -eq 1 ]
  [[ "$output" == *"missing dependency: krunkit"* ]]

  mock_command "krunkit"
  set +e
  output=$(check_dependencies "podman" 2>&1)
  status=$?
  set -e

  [ "$status" -eq 0 ]
}

@test "run_brew_install hides raw brew bundle output by default" {
  MANIFEST_BREWFILE="$BATS_TEST_TMPDIR/Brewfile"
  cat > "$MANIFEST_BREWFILE" <<'EOF'
brew "jq"
EOF
  METADATA_LINES=("jq"$'\t'"brew"$'\t'"package"$'\t'"jq --version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'"")

  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "brew" '
case "$1" in
  bundle)
    shift
    printf "%s\n" "$@" > "'"$BATS_TEST_TMPDIR"'/brew-bundle-args.txt"
    if printf "%s\n" "$@" | grep -qx -- "--no-lock"; then
      echo "Error: invalid option: --no-lock" >&2
      exit 1
    fi
    echo "Warning: Not upgrading jq, the latest version is already installed"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'

  run run_brew_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"Info: Applying Homebrew bundle"* ]]
  [[ "$output" == *"Change: Homebrew bundle applied"* ]]
  [[ "$output" != *"Warning: Not upgrading"* ]]
  run grep -qx -- "--file=$MANIFEST_BREWFILE" "$BATS_TEST_TMPDIR/brew-bundle-args.txt"
  [ "$status" -eq 0 ]
}

@test "run_brew_install applies Homebrew tap trust policy to brew bundle" {
  MANIFEST_BREWFILE="$BATS_TEST_TMPDIR/Brewfile"
  cat > "$MANIFEST_BREWFILE" <<'EOF'
brew "jq"
EOF
  METADATA_LINES=("jq"$'\t'"brew"$'\t'"package"$'\t'"jq --version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'"")

  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "brew" '
case "$1" in
  bundle)
    printf "%s\t%s\n" "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" "${HOMEBREW_NO_ENV_HINTS:-}" > "'"$BATS_TEST_TMPDIR"'/brew-policy-env.txt"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'

  run run_brew_install
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "1" && $2 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$BATS_TEST_TMPDIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
}

@test "run_brew_install skips formulae already satisfied by install checks" {
  MANIFEST_BREWFILE="$BATS_TEST_TMPDIR/Brewfile"
  cat > "$MANIFEST_BREWFILE" <<'EOF'
brew "openssh"
EOF
  METADATA_LINES=("openssh"$'\t'"brew"$'\t'"package"$'\t'"command -v sh"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"network"$'\t'"")

  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "brew" '
case "$1" in
  bundle)
    printf "%s\n" "$HOMEBREW_BUNDLE_BREW_SKIP" > "'"$BATS_TEST_TMPDIR"'/brew-bundle-skip.txt"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'

  run run_brew_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip: Homebrew bundle omitting 1 already satisfied entry"* ]]
  run grep -qx -- "openssh" "$BATS_TEST_TMPDIR/brew-bundle-skip.txt"
  [ "$status" -eq 0 ]
}

@test "run_brew_install shows raw brew output in verbose mode" {
  export VERBOSE="true"
  MANIFEST_BREWFILE="$BATS_TEST_TMPDIR/Brewfile"
  cat > "$MANIFEST_BREWFILE" <<'EOF'
brew "jq"
EOF
  METADATA_LINES=("jq"$'\t'"brew"$'\t'"package"$'\t'"jq --version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'"")

  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "brew" '
case "$1" in
  bundle)
    echo "bundle output"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'

  run run_brew_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"bundle output"* ]]
}

@test "run_brew_update upgrades only outdated selected tools and classifies taps as managed" {
  METADATA_LINES=(
    "felixkratz/formulae"$'\t'"brew"$'\t'"tap"$'\t'"brew tap | grep -q felixkratz/formulae"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
    "jq"$'\t'"brew"$'\t'"package"$'\t'"jq --version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
    "ghostty"$'\t'"brew"$'\t'"cask"$'\t'"ghostty --version"$'\t'"true"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )

  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "brew" '
printf "%s\t%s\t%s\t%s\n" "$*" "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" "${HOMEBREW_NO_ENV_HINTS:-}" "${HOMEBREW_NO_AUTO_UPDATE:-}" >> "'"$BATS_TEST_TMPDIR"'/brew-policy-env.txt"

case "$1 $2" in
  "list --formula")
    echo "jq"
    exit 0
    ;;
  "list --cask")
    echo "ghostty"
    exit 0
    ;;
esac

case "$1" in
  outdated)
    if [[ "$2" == "--formula" ]]; then
      echo "jq"
    fi
    exit 0
    ;;
  update)
    echo "brew update ran"
    exit 0
    ;;
  upgrade)
    if [[ "$2" == "--cask" ]]; then
      echo "unexpected cask upgrade"
      exit 1
    fi
    echo "upgraded $2"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'

  run run_brew_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip: Homebrew taps are managed repositories (1): felixkratz/formulae"* ]]
  [[ "$output" == *"Skip: Homebrew updates disabled by configuration (1): ghostty (cask)"* ]]
  [[ "$output" == *"Skip: Homebrew metadata refresh skipped; run 'make brew update' separately or set BREW_REFRESH=true"* ]]
  [[ "$output" == *"Info: Updating 1 Homebrew formula..."* ]]
  [[ "$output" == *"Change: Updated 1 Homebrew formula: jq"* ]]
  run grep -qx -- "update" "$MOCK_CALLS_DIR/brew.calls"
  [ "$status" -ne 0 ]
  assert_mock_called "brew" "upgrade jq"
  run awk -F '\t' '$1 == "upgrade jq" && $2 == "1" && $3 == "1" && $4 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$BATS_TEST_TMPDIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
}

@test "run_brew_update reports tap and skip_update entries without querying Homebrew" {
  METADATA_LINES=(
    "felixkratz/formulae"$'\t'"brew"$'\t'"tap"$'\t'"brew tap | grep -q felixkratz/formulae"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
    "jq"$'\t'"brew"$'\t'"package"$'\t'"jq --version"$'\t'"true"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
    "ghostty"$'\t'"brew"$'\t'"cask"$'\t'"ghostty --version"$'\t'"true"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )

  mock_command_with_script "brew" '
echo "unexpected brew call: $*" >&2
exit 1
'

  run run_brew_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip: Homebrew taps are managed repositories (1): felixkratz/formulae"* ]]
  [[ "$output" == *"Skip: Homebrew updates disabled by configuration (2): jq (package), ghostty (cask)"* ]]
  assert_mock_not_called "brew"
}

@test "run_brew_update can refresh Homebrew metadata when requested" {
  export BREW_REFRESH="true"
  METADATA_LINES=(
    "jq"$'\t'"brew"$'\t'"package"$'\t'"jq --version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )

  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "brew" '
printf "%s\t%s\t%s\t%s\n" "$*" "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" "${HOMEBREW_NO_ENV_HINTS:-}" "${HOMEBREW_NO_AUTO_UPDATE:-}" >> "'"$BATS_TEST_TMPDIR"'/brew-policy-env.txt"

case "$1 $2" in
  "list --formula")
    echo "jq"
    exit 0
    ;;
  "list --cask")
    exit 0
    ;;
esac

case "$1" in
  outdated)
    if [[ "$2" == "--formula" ]]; then
      echo "jq"
    fi
    exit 0
    ;;
  update)
    echo "brew update ran"
    exit 0
    ;;
  upgrade)
    echo "upgraded $2"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
'

  run run_brew_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Info: Refreshing Homebrew metadata..."* ]]
  assert_mock_called "brew" "update"
  assert_mock_called "brew" "upgrade jq"
  run awk -F '\t' '$1 == "update" && $2 == "1" && $3 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$BATS_TEST_TMPDIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
  run awk -F '\t' '$1 == "upgrade jq" && $2 == "1" && $3 == "1" && $4 == "1" { found = 1 } END { exit found ? 0 : 1 }' "$BATS_TEST_TMPDIR/brew-policy-env.txt"
  [ "$status" -eq 0 ]
}

@test "write_update_manifest records selected update tools and manager counts" {
  export UPDATE="true"
  export UPDATE_MANIFEST_PATH="$BATS_TEST_TMPDIR/update-plan.tsv"
  export BREW_REFRESH="false"
  RESOLVED_CONFIG_FILES=("$BATS_TEST_TMPDIR/_configs/host/common.yaml")
  # shellcheck disable=SC2034  # consumed by write_update_manifest
  AVAILABLE_MANAGERS=("brew" "manual")
  METADATA_LINES=(
    "jq"$'\t'"brew"$'\t'"package"$'\t'"jq --version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"data"$'\t'""
    "docker-desktop"$'\t'"manual"$'\t'"check"$'\t'"test -d /Applications/Docker.app"$'\t'"true"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"containers"$'\t'""
  )

  run write_update_manifest
  [ "$status" -eq 0 ]
  [ -f "$UPDATE_MANIFEST_PATH" ]
  run grep -F $'jq\tbrew\tpackage\tyes\tjq --version' "$UPDATE_MANIFEST_PATH"
  [ "$status" -eq 0 ]
  run grep -F $'docker-desktop\tmanual\tcheck\tno\ttest -d /Applications/Docker.app' "$UPDATE_MANIFEST_PATH"
  [ "$status" -eq 0 ]
  run grep -F $'brew\tpackage\t1\t1' "$UPDATE_MANIFEST_PATH"
  [ "$status" -eq 0 ]
}

@test "run_update_phase reports failed phases without suppressing exit status" {
  export UPDATE="true"
  # shellcheck disable=SC2034  # consumed by run_update_phase
  UPDATE_PHASE_INDEX=0
  # shellcheck disable=SC2034  # consumed by run_update_phase
  UPDATE_PHASE_TOTAL=1

  failing_update_step() {
    return 7
  }

  run run_update_phase "Failing demo phase" failing_update_step
  [ "$status" -eq 7 ]
  [[ "$output" == *"Info: Phase 1/1: Failing demo phase"* ]]
  [[ "$output" == *"Fail: Phase 1/1 failed after"* ]]
}

@test "run_arkade_batch builds a single batch command from the TSV manifest" {
  # shellcheck disable=SC2034  # consumed by the sourced installer
  METADATA_LINES=(
    "tool-alpha"$'\t'"arkade"$'\t'"get"$'\t'"tool-alpha version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'"--version 1.31.0"
    "tool-beta"$'\t'"arkade"$'\t'"get"$'\t'"tool-beta version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )
  # shellcheck disable=SC2034  # consumed by the sourced installer
  ARKADE_LINES=(
    "tool-alpha"$'\t'"--version 1.31.0"
    "tool-beta"$'\t'""
  )
  export DRY_RUN="true"
  mock_command "arkade"

  run run_arkade_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would execute: arkade get tool-alpha --version 1.31.0 tool-beta --parallel 10"* ]]
}

@test "run_arkade_batch reports refreshes as info during updates" {
  export UPDATE="true"
  # shellcheck disable=SC2034  # consumed by the sourced installer
  METADATA_LINES=(
    "tool-alpha"$'\t'"arkade"$'\t'"get"$'\t'"tool-alpha version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )
  # shellcheck disable=SC2034  # consumed by the sourced installer
  ARKADE_LINES=(
    "tool-alpha"$'\t'""
  )
  mock_command "tool-alpha"
  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "arkade" '
if [[ "$1" == "get" ]]; then
  echo "arkade refresh"
  exit 0
fi
exit 1
'

  run run_arkade_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Info: Refreshed 1 arkade tool(s)"* ]]
  [[ "$output" != *"Change: Refreshed 1 arkade tool(s)"* ]]
}

@test "run_code_extensions skips work when the VSCode CLI is unavailable" {
  METADATA_LINES=(
    "prettier-vscode"$'\t'"code"$'\t'"extension"$'\t'"code --list-extensions | grep -q esbenp.prettier-vscode"$'\t'"false"$'\t'"null"$'\t'"esbenp.prettier-vscode"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )
  export VSCODE_CLI="missing-code"

  run run_code_extensions
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip: VSCode CLI unavailable; skipping extension management"* ]]
}

@test "run_code_extensions batches installs for missing extensions" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  METADATA_LINES=(
    "prettier-vscode"$'\t'"code"$'\t'"extension"$'\t'"code --list-extensions | grep -q esbenp.prettier-vscode"$'\t'"false"$'\t'"null"$'\t'"esbenp.prettier-vscode"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )
  cat > "$MOCK_BIN_DIR/code" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_CALLS_DIR/code.calls"
if [[ "$1" == "--list-extensions" ]]; then
  exit 0
fi
echo "installing extensions"
EOF
  chmod +x "$MOCK_BIN_DIR/code"

  run run_code_extensions
  [ "$status" -eq 0 ]
  [[ "$output" == *"Change: Installed 1 VSCode extension(s)"* ]]
  assert_mock_called "code" "--install-extension esbenp.prettier-vscode"
}

@test "run_code_extensions uses VSCode updater during update mode" {
  export HOME="$BATS_TEST_TMPDIR/home"
  export UPDATE="true"
  mkdir -p "$HOME"
  METADATA_LINES=(
    "prettier-vscode"$'\t'"code"$'\t'"extension"$'\t'"code --list-extensions | grep -q esbenp.prettier-vscode"$'\t'"false"$'\t'"null"$'\t'"esbenp.prettier-vscode"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )
  cat > "$MOCK_BIN_DIR/code" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$MOCK_CALLS_DIR/code.calls"
case "$1" in
  --list-extensions)
    echo "esbenp.prettier-vscode"
    exit 0
    ;;
  --update-extensions)
    echo "updating extensions"
    exit 0
    ;;
  --install-extension)
    exit 2
    ;;
esac
exit 0
EOF
  chmod +x "$MOCK_BIN_DIR/code"

  run run_code_extensions
  [ "$status" -eq 0 ]
  [[ "$output" == *"Info: Updating VSCode extensions via profile-wide updater for 1 selected installed extension(s)..."* ]]
  [[ "$output" == *"Info: Updated VSCode extensions"* ]]
  assert_mock_called "code" "--update-extensions"
  run grep -q -- "--install-extension" "$MOCK_CALLS_DIR/code.calls"
  [ "$status" -ne 0 ]
}

@test "run_brew_fallback_if_needed installs brew packages through apt when Homebrew is unavailable" {
  METADATA_LINES=(
    "fakefd"$'\t'"brew"$'\t'"package"$'\t'"fakefd --version"$'\t'"false"$'\t'"fdfind"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )
  mock_apt_get
  mock_id 0
  command_exists() {
    case "$1" in
      apt-get|yq|which) return 0 ;;
      brew) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f command_exists

  run run_brew_fallback_if_needed
  [ "$status" -eq 0 ]
  assert_mock_called "apt-get" "install -y fdfind"
}

@test "run_direct_metadata_tools updates cargo binaries in batch when cargo-update is available" {
  export UPDATE="true"
  # shellcheck disable=SC2034  # consumed by the sourced installer
  METADATA_LINES=(
    "code2prompt"$'\t'"cargo"$'\t'"binary"$'\t'"code2prompt --version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )
  cat > "$MOCK_BIN_DIR/code2prompt" <<'EOF'
#!/usr/bin/env bash
echo "code2prompt 1.0.0"
EOF
  chmod +x "$MOCK_BIN_DIR/code2prompt"
  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "cargo" '
if [[ "$1" == "install-update" && "$2" == "--version" ]]; then
  echo "cargo-install-update 0.1"
  exit 0
fi
if [[ "$1" == "install-update" && "$2" == "-l" ]]; then
  echo "Package  Installed  Latest  Needs update"
  echo "code2prompt  1.0.0  1.1.0  Yes"
  exit 0
fi
if [[ "$1" == "install-update" ]]; then
  echo "updated cargo binaries"
  exit 0
fi
exit 1
'

  run run_direct_metadata_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"Change: Updated 1 cargo tool(s)"* ]]
  assert_mock_called "cargo" "install-update code2prompt"
}

@test "run_direct_metadata_tools skips cargo updates when all selected tools are current" {
  export UPDATE="true"
  # shellcheck disable=SC2034  # consumed by the sourced installer
  METADATA_LINES=(
    "code2prompt"$'\t'"cargo"$'\t'"binary"$'\t'"code2prompt --version"$'\t'"false"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"null"$'\t'"test"$'\t'""
  )
  cat > "$MOCK_BIN_DIR/code2prompt" <<'EOF'
#!/usr/bin/env bash
echo "code2prompt 1.0.0"
EOF
  chmod +x "$MOCK_BIN_DIR/code2prompt"
  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "cargo" '
if [[ "$1" == "install-update" && "$2" == "--version" ]]; then
  echo "cargo-install-update 0.1"
  exit 0
fi
if [[ "$1" == "install-update" && "$2" == "-l" ]]; then
  echo "Package  Installed  Latest  Needs update"
  exit 0
fi
if [[ "$1" == "install-update" ]]; then
  echo "unexpected cargo update run"
  exit 1
fi
exit 1
'

  run run_direct_metadata_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip: Selected cargo tools already up to date"* ]]
  [[ "$output" != *"Change: Updated"* ]]
}

@test "run_mas_update ignores malformed manifest entries" {
  # shellcheck disable=SC2034  # consumed by the sourced installer
  MAS_UPDATE_LINES=(
    $'\tmas\tapp\tcheck\tfalse\tnull\tnull\tnull\tnull\tnull\ttest\t'
  )
  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "mas" '
if [[ "$1" == "outdated" ]]; then
  exit 0
fi
exit 1
'

  run run_mas_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip: Ignoring malformed App Store manifest entry"* ]]
}

@test "run_mise_update skips when local runtimes are already current" {
  export UPDATE="true"
  touch "$REPO_ROOT/mise.toml"
  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "mise" '
if [[ "$1" == "outdated" ]]; then
  echo "{}"
  exit 0
fi
if [[ "$1" == "upgrade" ]]; then
  echo "unexpected mise upgrade run"
  exit 1
fi
exit 1
'

  run run_mise_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Info: Checking runtimes declared in mise.toml for updates..."* ]]
  [[ "$output" == *"Skip: Runtimes declared in mise.toml already up to date"* ]]
}

@test "main update clears the zsh init cache and suppresses no-op brew chatter" {
  local manifest_source="$BATS_TEST_TMPDIR/manifests"
  local zsh_cache_dir="$BATS_TEST_TMPDIR/cache/zsh-init"
  mkdir -p "$zsh_cache_dir"
  touch "$zsh_cache_dir/kubectl.zsh"

  write_manifest_bundle "$manifest_source" \
$'tap "felixkratz/formulae"\nbrew "jq"' \
$'kubectl\t' \
'[
  {"tool":"felixkratz/formulae","manager":"brew","type":"tap","check_command":"brew tap | grep -q felixkratz/formulae","install_args":[],"skip_update":false,"apt_package":null,"dependencies":[],"extension_id":null,"app_id":null,"description":null,"documentation_url":null,"category":"tap"},
  {"tool":"jq","manager":"brew","type":"package","check_command":"jq --version","install_args":[],"skip_update":false,"apt_package":null,"dependencies":[],"extension_id":null,"app_id":null,"description":null,"documentation_url":null,"category":"test"},
  {"tool":"kubectl","manager":"arkade","type":"get","check_command":"kubectl version --client","install_args":[],"skip_update":true,"apt_package":null,"dependencies":[],"extension_id":null,"app_id":null,"description":null,"documentation_url":null,"category":"kubernetes"}
]'
  create_manifest_generator "$manifest_source"

  export CONFIG_DIR="$BATS_TEST_TMPDIR/configs"
  mkdir -p "$CONFIG_DIR"
  touch "$CONFIG_DIR/test.yaml"
  export CONFIG_FILES=("test")
  export UPDATE="true"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"

  mock_command "which"
  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "brew" '
case "$1 $2" in
  "list --formula")
    echo "jq"
    exit 0
    ;;
  "list --cask")
    exit 0
    ;;
esac
case "$1" in
  outdated)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'
  # shellcheck disable=SC2016  # mock script is intentionally single-quoted
  mock_command_with_script "mise" '
if [[ "$1" == "outdated" ]]; then
  echo "{}"
  exit 0
fi
if [[ "$1" == "upgrade" ]]; then
  echo "unexpected mise upgrade run"
  exit 1
fi
exit 1
'
  mock_command "kubectl"

  run main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip: 1 Homebrew formula already up to date"* ]]
  [[ "$output" == *"Skip: Homebrew taps are managed repositories (1): felixkratz/formulae"* ]]
  [[ "$output" == *"Info: Checking runtimes declared in mise.toml for updates..."* ]]
  [[ "$output" == *"Skip: Runtimes declared in mise.toml already up to date"* ]]
  [[ "$output" != *"Warning: Not upgrading"* ]]
  [[ "$output" == *"Change: Cleared zsh init cache"* ]]
  [ ! -d "$zsh_cache_dir" ]
}

@test "main supports stow-only mode when CONFIG_FILES is empty" {
  export CONFIG_FILES=()
  export STOW="true"
  mock_command "yq"
  mock_command "which"
  mock_stow

  run main
  [ "$status" -eq 0 ]
  assert_mock_called "stow"
}
