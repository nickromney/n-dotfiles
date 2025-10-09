#!/usr/bin/env bats

setup() {
  # Set test environment
  export CONFIG_DIR="${BATS_TEST_DIRNAME}/../_configs"
}

# Helper to check YAML syntax
check_yaml() {
  local file="$1"
  if command -v yq >/dev/null 2>&1; then
    yq eval '.' "$file" >/dev/null 2>&1
  else
    # Basic check if yq not available
    grep -E '^\s*[a-zA-Z0-9_-]+:' "$file" >/dev/null
  fi
}

@test "configs: all YAML files have valid syntax" {
  local failed=0
  while IFS= read -r yaml_file; do
    if ! check_yaml "$yaml_file"; then
      echo "Invalid YAML: $yaml_file"
      ((failed++))
    fi
  done < <(find "$CONFIG_DIR" -name "*.yaml" -type f)

  [ "$failed" -eq 0 ]
}

@test "configs: shared/shell.yaml contains nvm" {
  run grep -q "nvm:" "$CONFIG_DIR/shared/shell.yaml"
  [ "$status" -eq 0 ]
}

@test "configs: focus/neovim.yaml exists" {
  [ -f "$CONFIG_DIR/focus/neovim.yaml" ]
}

@test "configs: focus/neovim.yaml contains neovim" {
  run grep -q "neovim:" "$CONFIG_DIR/focus/neovim.yaml"
  [ "$status" -eq 0 ]
}

@test "configs: focus/neovim.yaml contains language servers" {
  run grep -q "typescript-language-server:" "$CONFIG_DIR/focus/neovim.yaml"
  [ "$status" -eq 0 ]
  run grep -q "rust-analyzer:" "$CONFIG_DIR/focus/neovim.yaml"
  [ "$status" -eq 0 ]
  run grep -q "pyright:" "$CONFIG_DIR/focus/neovim.yaml"
  [ "$status" -eq 0 ]
}

@test "configs: host/common.yaml contains aerospace with install_args" {
  run grep -A5 "aerospace:" "$CONFIG_DIR/host/common.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "install_args" ]]
}

@test "configs: host/common.yaml contains borders with install_args" {
  run grep -A5 "borders:" "$CONFIG_DIR/host/common.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "install_args" ]]
}

@test "configs: shared/data-tools.yaml contains jqp with tap" {
  # Check that noahgorstein/tap exists
  run grep -q "noahgorstein/tap:" "$CONFIG_DIR/shared/data-tools.yaml"
  [ "$status" -eq 0 ]

  # Check that jqp has install_args
  run grep -A5 "jqp:" "$CONFIG_DIR/shared/data-tools.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "install_args" ]]
}

@test "configs: work.yaml handles empty tools section" {
  # This tests that our install.sh changes handle empty/null tools
  if [ -f "$CONFIG_DIR/host/work.yaml" ]; then
    run yq eval '.tools' "$CONFIG_DIR/host/work.yaml"
    # Should not error even if tools is null/empty
    [ "$status" -eq 0 ]
  else
    skip "work.yaml not present"
  fi
}

@test "configs: all tools have required fields" {
  local failed=0
  local yaml_files
  yaml_files=$(find "$CONFIG_DIR" -name "*.yaml" -type f)

  for yaml_file in $yaml_files; do
    # Skip if no tools section
    if ! yq eval '.tools' "$yaml_file" >/dev/null 2>&1; then
      continue
    fi

    # Check each tool has required fields
    local tools
    tools=$(yq eval '.tools | keys | .[]' "$yaml_file" 2>/dev/null || true)

    while IFS= read -r tool; do
      [[ -z "$tool" ]] && continue

      # Check for manager
      if ! yq eval ".tools.\"$tool\".manager" "$yaml_file" >/dev/null 2>&1; then
        echo "Missing manager for $tool in $yaml_file"
        ((failed++))
      fi

      # Check for type
      if ! yq eval ".tools.\"$tool\".type" "$yaml_file" >/dev/null 2>&1; then
        echo "Missing type for $tool in $yaml_file"
        ((failed++))
      fi

      # Check for check_command
      if ! yq eval ".tools.\"$tool\".check_command" "$yaml_file" >/dev/null 2>&1; then
        echo "Missing check_command for $tool in $yaml_file"
        ((failed++))
      fi
    done <<< "$tools"
  done

  [ "$failed" -eq 0 ]
}
