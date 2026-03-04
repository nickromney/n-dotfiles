#!/usr/bin/env bash
# Checks installed slicer version against the latest release in the registry.
# Requires: crane (arkade get crane), slicer

set -euo pipefail

# Check dependencies
if ! command -v crane >/dev/null 2>&1; then
  echo "crane not found. Install with: arkade get crane" >&2
  exit 1
fi

if ! command -v slicer >/dev/null 2>&1; then
  echo "slicer not found. Run install-slicer-mac.sh to install." >&2
  exit 1
fi

# Get latest semver tag from the registry
# Filters out digests (40-char hex), pre-release tags (containing -), and 'latest'
echo "Fetching tags from ghcr.io/openfaasltd/slicer..."
latest_tag=$(crane ls ghcr.io/openfaasltd/slicer 2>/dev/null \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V \
  | tail -1)

if [[ -z "$latest_tag" ]]; then
  echo "Error: could not determine latest version from registry." >&2
  exit 1
fi

# Get installed version — strip the commit hash suffix (e.g. 0.1.103-abc123 → 0.1.103)
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
  echo "Update available: $installed_semver → $latest_tag"
  echo "Run 'slicer update' to update."
fi
