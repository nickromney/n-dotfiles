#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_TMP_DIR
  TEST_TMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMP_DIR"
}

@test "generate-install-manifests creates Brewfile, arkade manifest, and metadata" {
  cat >"$TEST_TMP_DIR/core.yaml" <<'EOF'
tools:
  FelixKratz/formulae:
    manager: brew
    type: tap
    check_command: "brew tap | grep -q '^felixkratz/formulae$'"
  jq:
    manager: brew
    type: package
    check_command: command -v jq
  ghostty:
    manager: brew
    type: cask
    check_command: "brew list --cask | grep -q ghostty"
    skip_update: true
  kubectl:
    manager: arkade
    type: get
    check_command: command -v kubectl
    install_args: ["--path", "/tmp/tools"]
EOF

  cat >"$TEST_TMP_DIR/extras.yaml" <<'EOF'
tools:
  prettier-vscode:
    manager: code
    type: extension
    extension_id: esbenp.prettier-vscode
    check_command: "code --list-extensions | grep -q esbenp.prettier-vscode"
  bd:
    manager: brew
    type: package
    check_command: command -v bd
    apt_package: beads
    dependencies:
      - name: steveyegge/beads
        check_command: "brew tap | grep -q 'steveyegge/beads'"
  snagit:
    manager: manual
    type: check
    check_command: "[ -d '/Applications/Snagit.app' ]"
    description: "Screen capture tool"
    documentation_url: "https://www.techsmith.com/"
  things:
    manager: mas
    type: app
    app_id: 904280696
    check_command: "mas list | grep -q '^904280696'"
EOF

  run "$REPO_ROOT/scripts/generate-install-manifests.sh" "$TEST_TMP_DIR/out" "$TEST_TMP_DIR/core.yaml" "$TEST_TMP_DIR/extras.yaml"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP_DIR/out/Brewfile" ]
  [ -f "$TEST_TMP_DIR/out/arkade.tsv" ]
  [ -f "$TEST_TMP_DIR/out/metadata.json" ]

  grep -q 'tap "FelixKratz/formulae"' "$TEST_TMP_DIR/out/Brewfile"
  grep -q 'brew "jq"' "$TEST_TMP_DIR/out/Brewfile"
  grep -q 'brew "bd"' "$TEST_TMP_DIR/out/Brewfile"
  grep -q 'cask "ghostty"' "$TEST_TMP_DIR/out/Brewfile"
  grep -q 'mas "things", id: 904280696' "$TEST_TMP_DIR/out/Brewfile"

  grep -q $'^kubectl\t--path /tmp/tools$' "$TEST_TMP_DIR/out/arkade.tsv"

  run yq -r '.[] | select(.tool == "ghostty") | .skip_update' "$TEST_TMP_DIR/out/metadata.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run yq -r '.[] | select(.tool == "bd") | .apt_package' "$TEST_TMP_DIR/out/metadata.json"
  [ "$status" -eq 0 ]
  [ "$output" = "beads" ]

  run yq -r '.[] | select(.tool == "bd") | .dependencies[0].name' "$TEST_TMP_DIR/out/metadata.json"
  [ "$status" -eq 0 ]
  [ "$output" = "steveyegge/beads" ]

  run yq -r '.[] | select(.tool == "prettier-vscode") | .extension_id' "$TEST_TMP_DIR/out/metadata.json"
  [ "$status" -eq 0 ]
  [ "$output" = "esbenp.prettier-vscode" ]

  run yq -r '.[] | select(.tool == "snagit") | .documentation_url' "$TEST_TMP_DIR/out/metadata.json"
  [ "$status" -eq 0 ]
  [ "$output" = "https://www.techsmith.com/" ]
}
