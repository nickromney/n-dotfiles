#!/usr/bin/env bash
# Removes all slicer-mac installation artifacts.
# Defaults to dry-run mode; pass --execute to actually remove.
#
# Removal order:
#   1. slicer-mac services  — via `slicer-mac uninstall` if binary is present,
#                             otherwise plists are removed directly
#   2. slicer-mac bundle    — ~/slicer-mac directory and runtime artifacts
#   3. slicer CLI           — /usr/local/bin/slicer and openapi.yaml (requires sudo)
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

SLICER_MAC_BIN="$HOME/slicer-mac/slicer-mac"

# Paths requiring sudo (owned by root / in /usr/local/bin)
# NOTE: arkade is intentionally excluded — it is used by other tools.
SUDO_PATHS=(
  "/usr/local/bin/slicer"
  "/usr/local/bin/openapi.yaml"
)

# Paths owned by the current user (bundle directory)
USER_PATHS=(
  "$HOME/slicer"
  "$HOME/slicer-mac"
)

# Zsh completion cache files
ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-init"
ZSH_CACHE_PATHS=(
  "$ZSH_CACHE_DIR/slicer.zsh"
  "$ZSH_CACHE_DIR/slicer-mac.zsh"
)

# Plist paths — removed via `slicer-mac uninstall` if binary is present,
# otherwise removed directly
PLIST_PATHS=(
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
found_plists=()
found_zsh_cache=()
found_runtime_wrong=()   # artifacts in SCRIPT_DIR (wrong location)

for path in "${SUDO_PATHS[@]}"; do
  [[ -e "$path" ]] || [[ -L "$path" ]] && found_sudo+=("$path") || true
done

for path in "${USER_PATHS[@]}"; do
  [[ -e "$path" ]] || [[ -L "$path" ]] && found_user+=("$path") || true
done

for path in "${PLIST_PATHS[@]}"; do
  [[ -e "$path" ]] || [[ -L "$path" ]] && found_plists+=("$path") || true
done

for path in "${ZSH_CACHE_PATHS[@]}"; do
  [[ -f "$path" ]] && found_zsh_cache+=("$path") || true
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

has_slicer_mac=false
[[ -x "$SLICER_MAC_BIN" ]] && has_slicer_mac=true || true

found_count=$(( ${#found_sudo[@]} + ${#found_user[@]} + ${#found_plists[@]} + ${#found_zsh_cache[@]} + ${#found_runtime_wrong[@]} ))

if [[ $found_count -eq 0 ]] && ! $has_slicer_mac; then
  echo "Nothing to remove — no slicer artifacts found."
  exit 0
fi

# Report findings
echo "Slicer artifacts found:"
if $has_slicer_mac; then
  echo "  [service] slicer-mac binary present — will run 'slicer-mac uninstall'"
  for path in "${found_plists[@]+"${found_plists[@]}"}"; do
    echo "  [service]   $path"
  done
elif [[ ${#found_plists[@]} -gt 0 ]]; then
  for path in "${found_plists[@]+"${found_plists[@]}"}"; do
    echo "  [user] $path"
  done
fi
for path in "${found_user[@]+"${found_user[@]}"}"; do
  echo "  [user] $path"
done
for path in "${found_runtime_wrong[@]+"${found_runtime_wrong[@]}"}"; do
  echo "  [wrong-dir] $path"
done
for path in "${found_sudo[@]+"${found_sudo[@]}"}"; do
  echo "  [sudo] $path"
done
for path in "${found_zsh_cache[@]+"${found_zsh_cache[@]}"}"; do
  echo "  [cache] $path"
done
echo ""

if "$DRY_RUN"; then
  echo "[dry-run] No changes made. Pass --execute to remove."
  exit 0
fi

echo "Removing..."

# Phase 1: slicer-mac services
# Run uninstall before removing ~/slicer-mac (binary lives inside it)
if $has_slicer_mac; then
  echo "==> slicer-mac uninstall"
  "$SLICER_MAC_BIN" uninstall || true
fi
# Remove any plists not cleaned up by uninstall (e.g. if it was killed or not present)
for path in "${found_plists[@]+"${found_plists[@]}"}"; do
  if [[ -e "$path" ]]; then
    echo "  rm -f $path"
    rm -f "$path"
  fi
done

# Phase 2: slicer-mac bundle
for path in "${found_user[@]+"${found_user[@]}"}"; do
  echo "  rm -rf $path"
  rm -rf "$path"
done
for path in "${found_runtime_wrong[@]+"${found_runtime_wrong[@]}"}"; do
  echo "  rm -rf $path"
  rm -rf "$path"
done

# Phase 3: slicer CLI (requires sudo)
for path in "${found_sudo[@]+"${found_sudo[@]}"}"; do
  echo "  sudo rm -rf $path"
  sudo rm -rf "$path"
done

# Phase 4: zsh completion cache
for path in "${found_zsh_cache[@]+"${found_zsh_cache[@]}"}"; do
  echo "  rm -f $path"
  rm -f "$path"
done

echo ""
echo "Done."
