#!/usr/bin/env bash
# Checks installed slicer version against the latest release in the registry.
# Requires: crane (mise use -g crane@latest), slicer

set -euo pipefail

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: slicer-mac/check-slicer-version.sh [options]

Compare the installed slicer version with the latest stable release tag in GHCR.

Options:
  -h, --help  Show this help message

Examples:
  slicer-mac/check-slicer-version.sh
EOF

  exit "$exit_code"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
elif [[ $# -gt 0 ]]; then
  echo "Unknown argument: $1" >&2
  usage 1
fi

if ! command -v crane >/dev/null 2>&1; then
  echo "crane not found. Install with: mise use -g crane@latest" >&2
  exit 1
fi

if ! command -v slicer >/dev/null 2>&1; then
  echo "slicer not found. Run install-slicer-mac.sh to install." >&2
  exit 1
fi

echo "Fetching tags from ghcr.io/openfaasltd/slicer..."
latest_tag=$(crane ls ghcr.io/openfaasltd/slicer 2>/dev/null \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V \
  | tail -1)

if [[ -z "$latest_tag" ]]; then
  echo "Error: could not determine latest version from registry." >&2
  exit 1
fi

installed_full=$(slicer version 2>/dev/null | grep '^Version:' | awk '{print $2}')
installed_semver="${installed_full%%-*}"

if [[ -z "$installed_semver" ]]; then
  echo "Error: could not determine installed slicer version." >&2
  exit 1
fi

echo ""
echo "  Latest available: $latest_tag"
echo "  Installed:        $installed_semver"
echo ""

if [[ "$installed_semver" == "$latest_tag" ]]; then
  echo "Up to date."
else
  echo "Update available: $installed_semver -> $latest_tag"
  echo "Run 'slicer update' to update."
fi
