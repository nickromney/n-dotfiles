#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTANCE_NAME="${LIMA_INSTANCE:-ndotfiles-ubuntu2404}"
CONFIG_FILE="${LIMA_CONFIG_FILE:-$SCRIPT_DIR/ubuntu-24.04.yaml}"
START_TIMEOUT="${LIMA_START_TIMEOUT:-30m}"

usage() {
  cat <<EOF
Usage: $0 <up|run|test|status|down|destroy>

Commands:
  up       Start (or create + start) the Ubuntu 24.04 test VM
  run      Run POSIX/non-mac smoke tests inside the VM
  test     Equivalent to: up + run
  status   Show status for the test VM
  down     Stop the test VM (preserves state)
  destroy  Delete the test VM
EOF
}

require_limactl() {
  if ! command -v limactl >/dev/null 2>&1; then
    echo "ERROR: limactl is required. Install with: brew install lima"
    exit 1
  fi
}

instance_exists() {
  limactl list --format '{{.Name}}' | grep -qx "$INSTANCE_NAME"
}

start_instance() {
  require_limactl

  if instance_exists; then
    echo "Starting existing Lima VM: $INSTANCE_NAME"
    limactl start "$INSTANCE_NAME" --tty=false --timeout="$START_TIMEOUT"
  else
    echo "Creating and starting Lima VM: $INSTANCE_NAME"
    limactl start --name="$INSTANCE_NAME" "$CONFIG_FILE" --tty=false --timeout="$START_TIMEOUT"
  fi
}

run_smoke_tests() {
  require_limactl

  echo "Running POSIX/non-mac smoke tests in $INSTANCE_NAME..."
  limactl shell "$INSTANCE_NAME" -- env REPO_HINT="$REPO_ROOT" bash -lc '
    set -euo pipefail
    repo="${REPO_HINT:-}"
    if [[ -z "$repo" || ! -d "$repo" ]]; then
      for base in "$HOME" /Users /home; do
        found=$(find "$base" -maxdepth 6 -path "*/n-dotfiles" -type d 2>/dev/null | head -1 || true)
        if [[ -n "$found" ]]; then
          repo="$found"
          break
        fi
      done
    fi

    if [[ -z "$repo" || ! -d "$repo" ]]; then
      echo "ERROR: Could not locate n-dotfiles repo in VM."
      exit 1
    fi

    bash "$repo/_test/lima/run-posix-smoke.sh" "$repo"
  '
}

show_status() {
  require_limactl
  if instance_exists; then
    printf "NAME\tSTATUS\tARCH\tCPUS\tMEMORY\n"
    limactl list --format '{{.Name}},{{.Status}},{{.Arch}},{{.CPUs}},{{.Memory}}' \
      | awk -F ',' -v name="$INSTANCE_NAME" '$1 == name { printf "%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5 }'
  else
    echo "Lima instance '$INSTANCE_NAME' does not exist."
  fi
}

stop_instance() {
  require_limactl
  limactl stop "$INSTANCE_NAME"
}

destroy_instance() {
  require_limactl
  limactl delete --force "$INSTANCE_NAME"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  case "$1" in
    up)
      start_instance
      ;;
    run)
      run_smoke_tests
      ;;
    test)
      start_instance
      run_smoke_tests
      ;;
    status)
      show_status
      ;;
    down)
      stop_instance
      ;;
    destroy)
      destroy_instance
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
