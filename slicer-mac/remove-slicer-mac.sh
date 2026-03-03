#!/usr/bin/env bash
# Removes all slicer-mac installation artifacts.
# Defaults to dry-run mode; pass --execute to actually remove.
#
# Paths are derived from auditing https://get.slicervm.com (get.sh):
#   - installs arkade to /usr/local/bin/arkade (excluded — used by other tools)
#   - installs slicer binary + openapi.yaml to /usr/local/bin/
# And from: slicer install slicer-mac ~/slicer-mac
# And from: slicer-mac install [--no-tray]
# And from: slicer-mac up (runtime artifacts, may land in wrong dir if not cd'd first)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=true

for arg in "$@"; do
  case "$arg" in
    --execute) DRY_RUN=false ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Paths requiring sudo (owned by root / in /usr/local/bin)
# NOTE: arkade is intentionally excluded — it is used by other tools.
SUDO_PATHS=(
  "/usr/local/bin/slicer"
  "/usr/local/bin/openapi.yaml"
)

# Paths owned by the current user
USER_PATHS=(
  "$HOME/slicer"
  "$HOME/slicer-mac"
  "$HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.plist"
  "$HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.tray.plist"
)

# Runtime artifact globs — checked in SCRIPT_DIR (wrong-dir cleanup) and ~/slicer-mac
# These are created by `slicer-mac up` relative to the working directory.
RUNTIME_DIRS=(
  ".sbox-runtime"
  ".slicer-configdrive"
  ".slicer-power-events"
  "kernel"
  "oci-cache"
)
RUNTIME_GLOBS=(
  "slicer*.sock"
  "slicer*.img"
  "slicer*.log"
  "slicer-power.log"
)

# Build list of what actually exists
found_sudo=()
found_user=()
found_runtime_wrong=()   # artifacts in SCRIPT_DIR (wrong location)

for path in "${SUDO_PATHS[@]}"; do
  [[ -e "$path" ]] || [[ -L "$path" ]] && found_sudo+=("$path") || true
done

for path in "${USER_PATHS[@]}"; do
  [[ -e "$path" ]] || [[ -L "$path" ]] && found_user+=("$path") || true
done

# Only scan SCRIPT_DIR for misplaced runtime artifacts if it is not ~/slicer-mac
if [[ "$SCRIPT_DIR" != "$HOME/slicer-mac" ]] && [[ -d "$SCRIPT_DIR" ]]; then
  for name in "${RUNTIME_DIRS[@]}"; do
    path="$SCRIPT_DIR/$name"
    [[ -e "$path" ]] && found_runtime_wrong+=("$path") || true
  done
  for glob in "${RUNTIME_GLOBS[@]}"; do
    for path in "$SCRIPT_DIR"/$glob; do
      [[ -e "$path" ]] && found_runtime_wrong+=("$path") || true
    done
  done
fi

found_count=$(( ${#found_sudo[@]} + ${#found_user[@]} + ${#found_runtime_wrong[@]} ))

if [[ $found_count -eq 0 ]]; then
  echo "Nothing to remove — no slicer artifacts found."
  exit 0
fi

echo "Found $found_count slicer artifact(s):"
for path in "${found_sudo[@]+"${found_sudo[@]}"}"; do
  echo "  [sudo] $path"
done
for path in "${found_user[@]+"${found_user[@]}"}"; do
  echo "  [user] $path"
done
for path in "${found_runtime_wrong[@]+"${found_runtime_wrong[@]}"}"; do
  echo "  [wrong-dir] $path"
done
echo ""

if "$DRY_RUN"; then
  echo "[dry-run] No changes made. Pass --execute to remove."
  exit 0
fi

echo "Removing..."
for path in "${found_sudo[@]+"${found_sudo[@]}"}"; do
  echo "  sudo rm -rf $path"
  sudo rm -rf "$path"
done
for path in "${found_user[@]+"${found_user[@]}"}"; do
  echo "  rm -rf $path"
  rm -rf "$path"
done
for path in "${found_runtime_wrong[@]+"${found_runtime_wrong[@]}"}"; do
  echo "  rm -rf $path"
  rm -rf "$path"
done

echo ""
echo "Done."
