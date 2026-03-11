#!/usr/bin/env bash
# Removes all slicer-mac installation artifacts.
# Defaults to dry-run mode; pass --execute to actually remove.
#
# Removal order:
#   0. Kill running slicer processes
#   1. slicer-mac services  — launchctl bootout (by label), then plist removal
#   2. slicer-mac bundle    — ~/slicer-mac directory and runtime artifacts
#   3. slicer CLI           — /usr/local/bin/slicer and openapi.yaml (requires sudo)
#   4. Zsh cache + crash reporter artifacts
#
# Paths are derived from auditing https://get.slicervm.com (get.sh):
#   - installs arkade to /usr/local/bin/arkade (excluded — used by other tools)
#   - installs slicer binary + openapi.yaml to /usr/local/bin/
# And from: slicer install slicer-mac ~/slicer-mac
# And from: slicer-mac install [--no-tray]
# And from: slicer-mac up (runtime artifacts, may land in wrong dir if not cd'd first)
#
# NOTE: After running --execute, also check:
#   System Settings → General → Login Items & Extensions → Allow in the Background
#   and remove any remaining slicer-tray entry manually.

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

# Process names to kill before removing artifacts.
# Prevents processes writing new files after removal and avoids triggering
# macOS "App Background Activity" consent dialogs from the slicer-mac binary.
KILL_PROCS=(
  "slicer-tray"
  "slicer-mac"
)

# LaunchAgent service labels — used for launchctl bootout.
# Deregisters services even if the plist has already been removed.
PLIST_SERVICE_LABELS=(
  "com.openfaasltd.slicer-mac"
  "com.openfaasltd.slicer-mac.tray"
)

# Plist paths — unloaded via launchctl then removed directly
PLIST_PATHS=(
  "$HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.plist"
  "$HOME/Library/LaunchAgents/com.openfaasltd.slicer-mac.tray.plist"
)

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

# Crash reporter artifacts left by crashed slicer processes
CRASH_REPORTER_DIR="$HOME/Library/Application Support/CrashReporter"
CRASH_REPORTER_GLOB="slicer-mac_*.plist"

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
found_running_procs=()
found_sudo=()
found_user=()
found_plists=()
found_zsh_cache=()
found_crash_reporter=()
found_runtime_wrong=()   # artifacts in SCRIPT_DIR (wrong location)

for name in "${KILL_PROCS[@]}"; do
  pgrep -x "$name" &>/dev/null && found_running_procs+=("$name") || true
done

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

for path in "$CRASH_REPORTER_DIR"/$CRASH_REPORTER_GLOB; do
  [[ -e "$path" ]] && found_crash_reporter+=("$path") || true
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

found_count=$(( ${#found_running_procs[@]} + ${#found_sudo[@]} + ${#found_user[@]} + ${#found_plists[@]} + ${#found_zsh_cache[@]} + ${#found_runtime_wrong[@]} + ${#found_crash_reporter[@]} ))

if [[ $found_count -eq 0 ]]; then
  echo "Nothing to remove — no slicer artifacts found."
  echo ""
  echo "NOTE: Check System Settings → General → Login Items & Extensions → Allow in the Background"
  echo "and remove any remaining slicer-tray entry manually if present."
  exit 0
fi

# Report findings
echo "Slicer artifacts found:"
for name in "${found_running_procs[@]+"${found_running_procs[@]}"}"; do
  echo "  [process]  $name (running)"
done
for path in "${found_plists[@]+"${found_plists[@]}"}"; do
  echo "  [plist]    $path"
done
for path in "${found_user[@]+"${found_user[@]}"}"; do
  echo "  [user]     $path"
done
for path in "${found_runtime_wrong[@]+"${found_runtime_wrong[@]}"}"; do
  echo "  [wrong-dir] $path"
done
for path in "${found_sudo[@]+"${found_sudo[@]}"}"; do
  echo "  [sudo]     $path"
done
for path in "${found_zsh_cache[@]+"${found_zsh_cache[@]}"}"; do
  echo "  [cache]    $path"
done
for path in "${found_crash_reporter[@]+"${found_crash_reporter[@]}"}"; do
  echo "  [crash]    $path"
done
echo ""

if "$DRY_RUN"; then
  echo "[dry-run] No changes made. Pass --execute to remove."
  echo ""
  echo "NOTE: After running --execute, also check:"
  echo "  System Settings → General → Login Items & Extensions → Allow in the Background"
  echo "  and remove any remaining slicer-tray entry manually."
  exit 0
fi

echo "Removing..."

# Phase 0: Kill running slicer processes
# Must happen before file removal to prevent processes recreating directories/logs.
for name in "${found_running_procs[@]+"${found_running_procs[@]}"}"; do
  echo "  pkill -x $name"
  pkill -x "$name" || true
done

# Phase 1: slicer-mac services
# Use launchctl bootout by service label — deregisters even if plist is already gone.
# Then unload by plist path and remove (belt-and-suspenders).
for label in "${PLIST_SERVICE_LABELS[@]}"; do
  if launchctl list "$label" &>/dev/null; then
    echo "  launchctl bootout gui/$(id -u)/$label"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  fi
done
for path in "${found_plists[@]+"${found_plists[@]}"}"; do
  if [[ -e "$path" ]]; then
    echo "  launchctl unload $path"
    launchctl unload "$path" 2>/dev/null || true
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

# Phase 4: Zsh completion cache and crash reporter artifacts
for path in "${found_zsh_cache[@]+"${found_zsh_cache[@]}"}"; do
  echo "  rm -f $path"
  rm -f "$path"
done
for path in "${found_crash_reporter[@]+"${found_crash_reporter[@]}"}"; do
  echo "  rm -f $path"
  rm -f "$path"
done

echo ""
echo "Done."
echo ""
echo "NOTE: Check System Settings → General → Login Items & Extensions → Allow in the Background"
echo "and remove any remaining slicer-tray entry manually if present."
