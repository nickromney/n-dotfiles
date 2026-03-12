#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/generate-install-manifests.sh <output-dir> <config> [<config> ...]

Generates:
  - Brewfile
  - arkade.tsv
  - metadata.json
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

output_dir=$1
shift

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$output_dir"

resolve_config_file() {
  local config=$1
  local candidate=$config

  if [[ "$candidate" != *.yaml && "$candidate" != *.yml ]]; then
    candidate="${candidate}.yaml"
  fi

  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -f "$repo_root/_configs/$candidate" ]]; then
    printf '%s\n' "$repo_root/_configs/$candidate"
    return 0
  fi

  printf 'ERROR: Could not find config: %s\n' "$config" >&2
  return 1
}

arkade_tmp=$(mktemp)
metadata_tmp=$(mktemp)

cleanup() {
  rm -f "$arkade_tmp" "$metadata_tmp"
}
trap cleanup EXIT

"$repo_root/scripts/generate-brewfile.sh" "$output_dir/Brewfile" "$@"

for config in "$@"; do
  cfg_file=$(resolve_config_file "$config")

  yq -r '
    .tools // {} | to_entries[]
    | select(.value.manager == "arkade" and .value.type == "get")
    | .key + "\t" + ((.value.install_args // []) | join(" "))
  ' "$cfg_file" >>"$arkade_tmp"

  yq -o=json -I=0 '
    .tools // {} | to_entries[]
    | {
        "tool": .key,
        "manager": (.value.manager // ""),
        "type": (.value.type // ""),
        "check_command": (.value.check_command // ""),
        "install_args": (.value.install_args // []),
        "skip_update": (.value.skip_update // false),
        "apt_package": (.value.apt_package // null),
        "extension_id": (.value.extension_id // null),
        "app_id": (.value.app_id // null),
        "description": (.value.description // null),
        "documentation_url": (.value.documentation_url // null),
        "category": (.value.category // null),
        "dependencies": (.value.dependencies // [])
      }
  ' "$cfg_file" >>"$metadata_tmp"
done

sort -u "$arkade_tmp" | sed '/^[[:space:]]*$/d' >"$output_dir/arkade.tsv"

{
  echo "["
  awk '
    NF && !seen[$0]++ {
      if (count > 0) {
        printf(",\n")
      }
      printf("%s", $0)
      count++
    }
    END {
      if (count > 0) {
        printf("\n")
      }
    }
  ' "$metadata_tmp"
  echo "]"
} >"$output_dir/metadata.json"

printf 'Generated install manifests in %s\n' "$output_dir"
