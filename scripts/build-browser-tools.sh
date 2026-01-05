#!/usr/bin/env bash
set -euo pipefail

main() {
  local script_dir
  local repo_root
  local bin_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"
  bin_dir="${repo_root}/bin"

  if ! command -v bun >/dev/null 2>&1; then
    echo "bun is required to build browser-tools." >&2
    echo "Install bun: https://bun.sh" >&2
    exit 1
  fi

  if [ ! -f "${script_dir}/package.json" ]; then
    echo "Missing ${script_dir}/package.json for browser-tools dependencies." >&2
    exit 1
  fi

  if [ ! -d "${script_dir}/node_modules/commander" ] || [ ! -d "${script_dir}/node_modules/puppeteer-core" ]; then
    bun install --cwd "${script_dir}"
  fi

  mkdir -p "$bin_dir"
  bun build "${script_dir}/browser-tools.ts" --compile --target bun --outfile "${bin_dir}/browser-tools"
  echo "Built ${bin_dir}/browser-tools"
}

main "$@"
