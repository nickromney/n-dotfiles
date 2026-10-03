#!/usr/bin/env bash
# Read-only process-family memory sampler for macOS.

set -euo pipefail

export LC_ALL=C

FORMAT="table"
INTERVAL=60
COUNT=1
USE_DEFAULT_GROUPS=true

PS_CMD="${MEMORY_REPORT_PS_CMD:-ps}"
FOOTPRINT_CMD="${MEMORY_REPORT_FOOTPRINT_CMD:-footprint}"
MEMORY_PRESSURE_CMD="${MEMORY_REPORT_MEMORY_PRESSURE_CMD:-memory_pressure}"
SYSCTL_CMD="${MEMORY_REPORT_SYSCTL_CMD:-sysctl}"
UNAME_CMD="${MEMORY_REPORT_UNAME_CMD:-uname}"
DATE_CMD="${MEMORY_REPORT_DATE_CMD:-date}"
SLEEP_CMD="${MEMORY_REPORT_SLEEP_CMD:-sleep}"
SELF_PID="${MEMORY_REPORT_SELF_PID:-$$}"

LABELS=()
PATTERNS=()

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/macos-memory-report.sh [options]

Sample RSS, physical footprint, peak footprint, and CPU for related macOS
process families. The report is read-only. Physical footprint is the primary
comparison metric; RSS is included because it is familiar but counts shared
framework pages in every process.

Options:
  -h, --help                 Show this help message
      --format <table|tsv>   Select human-readable or tab-separated output
      --interval <seconds>   Seconds between samples (default: 60)
      --count <number>       Number of samples to collect (default: 1)
      --group <label=regex>  Add a process family using a ps command regex
      --no-default-groups    Profile only groups supplied with --group

Default groups:
  AeroSpace, borders, Bartender, Homerow, Superkey, AudioPriorityBar,
  Pearcleaner, Bloom, Chops, Clearly, Spokenly, Wispr Flow, Brave,
  Google Chrome, Docker Desktop, Silo, Ghostty, and RubyMine.

Environment overrides (useful for tests):
  MEMORY_REPORT_PS_CMD, MEMORY_REPORT_FOOTPRINT_CMD,
  MEMORY_REPORT_MEMORY_PRESSURE_CMD, MEMORY_REPORT_SYSCTL_CMD,
  MEMORY_REPORT_UNAME_CMD, MEMORY_REPORT_DATE_CMD, MEMORY_REPORT_SLEEP_CMD

Examples:
  scripts/macos-memory-report.sh
  scripts/macos-memory-report.sh --count 12 --interval 300
  scripts/macos-memory-report.sh --format tsv > /tmp/mac-memory.tsv
  scripts/macos-memory-report.sh --no-default-groups \
    --group 'Wispr Flow=/Applications/Wispr Flow[.]app/'

Notes:
  Footprint peak is the sum of each process's lifetime peak. Those peaks may
  have happened at different times, so treat the value as an upper bound.
  A process that exits during a sample may have RSS but no footprint value.
EOF

  exit "$exit_code"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_value() {
  [[ -n "${2:-}" ]] || die "$1 requires a value"
}

require_positive_integer() {
  local option="$1"
  local value="$2"

  [[ "$value" =~ ^[1-9][0-9]*$ ]] || die "$option requires a positive integer"
}

add_group() {
  local specification="$1"
  local label pattern

  [[ "$specification" == *=* ]] || die "--group requires label=regex"
  label="${specification%%=*}"
  pattern="${specification#*=}"
  [[ -n "$label" && -n "$pattern" ]] || die "--group requires non-empty label and regex"
  [[ "$label" != *$'\t'* && "$label" != *$'\n'* ]] || die "--group label cannot contain tabs or newlines"

  LABELS+=("$label")
  PATTERNS+=("$pattern")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage 0
      ;;
    --format)
      require_value "$1" "${2:-}"
      FORMAT="$2"
      shift 2
      ;;
    --interval)
      require_value "$1" "${2:-}"
      require_positive_integer "$1" "$2"
      INTERVAL="$2"
      shift 2
      ;;
    --count)
      require_value "$1" "${2:-}"
      require_positive_integer "$1" "$2"
      COUNT="$2"
      shift 2
      ;;
    --group)
      require_value "$1" "${2:-}"
      add_group "$2"
      shift 2
      ;;
    --no-default-groups)
      USE_DEFAULT_GROUPS=false
      shift
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

case "$FORMAT" in
  table | tsv) ;;
  *) die "--format must be table or tsv" ;;
esac

if [[ "$USE_DEFAULT_GROUPS" == "true" ]]; then
  LABELS=(
    "AeroSpace"
    "borders"
    "Bartender"
    "Homerow"
    "Superkey"
    "AudioPriorityBar"
    "Pearcleaner"
    "Bloom"
    "Chops"
    "Clearly"
    "Spokenly"
    "Wispr Flow"
    "Brave"
    "Google Chrome"
    "Docker Desktop"
    "Silo"
    "Ghostty"
    "RubyMine"
    ${LABELS[@]+"${LABELS[@]}"}
  )
  PATTERNS=(
    "/Applications/AeroSpace[.]app/"
    "/Applications/Borders[.]app/|(^|[[:space:]])(/opt/homebrew/bin/)?borders([[:space:]]|$)"
    "/Applications/Bartender 6[.]app/"
    "/Applications/Homerow[.]app/"
    "/Applications/Superkey[.]app/"
    "/AudioPriorityBar[.]app/"
    "/Applications/Pearcleaner[.]app/|PearcleanerSentinel"
    "/Applications/Bloom[.]app/"
    "/Applications/Chops[.]app/"
    "/Applications/Clearly[.]app/|com[.]sabotage[.]clearly"
    "/Applications/Spokenly[.]app/"
    "/Applications/Wispr Flow[.]app/"
    "/Applications/Brave Browser[.]app/"
    "/Applications/Google Chrome[.]app/"
    "/Applications/Docker[.]app/|com[.]docker[.]vmnetd"
    "/Applications/Silo[.]app/"
    "/Applications/Ghostty[.]app/"
    "/Applications/RubyMine[.]app/|/Caches/JetBrains/RubyMine[^/]*/semantic-search/"
    ${PATTERNS[@]+"${PATTERNS[@]}"}
  )
fi

[[ ${#LABELS[@]} -gt 0 ]] || die "No process groups selected"

for pattern in "${PATTERNS[@]}"; do
  awk -v pattern="$pattern" 'BEGIN {matched = ("" ~ pattern); exit matched && 0}' </dev/null 2>/dev/null \
    || die "Invalid process-group regex: $pattern"
done

[[ "$($UNAME_CMD -s)" == "Darwin" ]] || die "macOS is required"
command -v "$PS_CMD" >/dev/null 2>&1 || die "ps command not found: $PS_CMD"
command -v "$FOOTPRINT_CMD" >/dev/null 2>&1 || die "footprint command not found: $FOOTPRINT_CMD"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macos-memory-report.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

format_mib() {
  awk -v bytes="$1" 'BEGIN {printf "%.1f", bytes / 1048576}'
}

format_rss_mib() {
  awk -v kib="$1" 'BEGIN {printf "%.1f", kib / 1024}'
}

write_system_summary() {
  local memory_bytes="unknown"
  local memory_gib="unknown"
  local pressure_file="$TMP_DIR/memory-pressure.txt"
  local free_percent="unknown"
  local page_size="unknown"
  local compressor_pages="unknown"
  local compressor_mib="unknown"

  if command -v "$SYSCTL_CMD" >/dev/null 2>&1; then
    memory_bytes="$($SYSCTL_CMD -n hw.memsize 2>/dev/null || true)"
    if [[ "$memory_bytes" =~ ^[0-9]+$ ]]; then
      memory_gib="$(awk -v bytes="$memory_bytes" 'BEGIN {printf "%.1f", bytes / 1073741824}')"
    fi
  fi

  if command -v "$MEMORY_PRESSURE_CMD" >/dev/null 2>&1 && "$MEMORY_PRESSURE_CMD" >"$pressure_file" 2>/dev/null; then
    free_percent="$(awk '/System-wide memory free percentage:/ {gsub(/%/, "", $5); print $5; exit}' "$pressure_file")"
    page_size="$(awk '/page size of/ {gsub(/[^0-9]/, "", $NF); print $NF; exit}' "$pressure_file")"
    compressor_pages="$(awk '/Pages used by compressor:/ {print $5; exit}' "$pressure_file")"
    if [[ "$page_size" =~ ^[0-9]+$ && "$compressor_pages" =~ ^[0-9]+$ ]]; then
      compressor_mib="$(awk -v pages="$compressor_pages" -v size="$page_size" 'BEGIN {printf "%.1f", pages * size / 1048576}')"
    fi
  fi

  if [[ "$FORMAT" == "table" ]]; then
    printf 'System: %s GiB RAM | free: %s%% | compressor: %s MiB\n\n' \
      "$memory_gib" "$free_percent" "$compressor_mib"
  else
    printf '# system_memory_gib=%s free_percent=%s compressor_mib=%s\n' \
      "$memory_gib" "$free_percent" "$compressor_mib"
  fi
}

parse_footprint() {
  local raw_file="$1"
  local parsed_file="$2"

  awk '
    /Footprint: [0-9]+ B/ {
      pid=$0
      sub(/^.*\[/, "", pid)
      sub(/\].*$/, "", pid)
      footprint=$0
      sub(/^.*Footprint: /, "", footprint)
      sub(/ B.*$/, "", footprint)
      current_pid=pid
      current[pid]=footprint
    }
    /phys_footprint_peak:/ && current_pid != "" {
      peak[current_pid]=$2
    }
    END {
      for (pid in current) {
        printf "%s\t%s\t%s\n", pid, current[pid], peak[pid]
      }
    }
  ' "$raw_file" >"$parsed_file"
}

print_header() {
  if [[ "$FORMAT" == "table" ]]; then
    printf '%-24s  %-18s  %5s  %10s  %14s  %14s  %8s\n' \
      "Time" "Group" "Procs" "RSS MiB" "Footprint MiB" "Peak sum MiB" "CPU %"
    printf '%-24s  %-18s  %5s  %10s  %14s  %14s  %8s\n' \
      "------------------------" "------------------" "-----" "----------" "--------------" "------------" "--------"
  else
    printf 'timestamp\tgroup\tprocesses\trss_mib\tfootprint_mib\tpeak_sum_mib\tcpu_percent\n'
  fi
}

capture_sample() {
  local sample_number="$1"
  local timestamp ps_file footprint_raw footprint_map
  local index label pattern group_file
  local process_count rss_kib cpu_total pid current_bytes peak_bytes
  local footprint_total peak_total rss_mib footprint_mib peak_mib
  local footprint_args=(--noCategories --format bytes)

  timestamp="$($DATE_CMD '+%Y-%m-%dT%H:%M:%S%z')"
  ps_file="$TMP_DIR/ps-$sample_number.txt"
  footprint_raw="$TMP_DIR/footprint-$sample_number.txt"
  footprint_map="$TMP_DIR/footprint-$sample_number.tsv"

  "$PS_CMD" -axo pid=,ppid=,rss=,%cpu=,etime=,command= >"$ps_file"

  for index in "${!LABELS[@]}"; do
    pattern="${PATTERNS[$index]}"
    group_file="$TMP_DIR/group-$sample_number-$index.txt"
    awk -v pattern="$pattern" -v self_pid="$SELF_PID" '
      {
        pid[NR]=$1
        parent[$1]=$2
        line[NR]=$0
      }
      END {
        current=self_pid
        while (current != "" && current != 0 && !excluded[current]) {
          excluded[current]=1
          current=parent[current]
        }
        for (row=1; row <= NR; row++) {
          if (!excluded[pid[row]] && line[row] ~ pattern) print line[row]
        }
      }
    ' "$ps_file" >"$group_file"
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      footprint_args+=(-p "$pid")
    done < <(awk '{print $1}' "$group_file")
  done

  : >"$footprint_raw"
  if [[ ${#footprint_args[@]} -gt 4 ]]; then
    "$FOOTPRINT_CMD" "${footprint_args[@]}" >"$footprint_raw" 2>"$TMP_DIR/footprint-$sample_number.err" || true
  fi
  parse_footprint "$footprint_raw" "$footprint_map"

  for index in "${!LABELS[@]}"; do
    label="${LABELS[$index]}"
    group_file="$TMP_DIR/group-$sample_number-$index.txt"
    process_count="$(awk 'END {print NR + 0}' "$group_file")"
    rss_kib="$(awk '{sum += $3} END {print sum + 0}' "$group_file")"
    cpu_total="$(awk '{sum += $4} END {printf "%.1f", sum + 0}' "$group_file")"
    footprint_total=0
    peak_total=0

    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      current_bytes="$(awk -F'\t' -v target="$pid" '$1 == target {print $2; exit}' "$footprint_map")"
      peak_bytes="$(awk -F'\t' -v target="$pid" '$1 == target {print $3; exit}' "$footprint_map")"
      [[ "$current_bytes" =~ ^[0-9]+$ ]] && footprint_total=$((footprint_total + current_bytes))
      [[ "$peak_bytes" =~ ^[0-9]+$ ]] && peak_total=$((peak_total + peak_bytes))
    done < <(awk '{print $1}' "$group_file")

    rss_mib="$(format_rss_mib "$rss_kib")"
    footprint_mib="$(format_mib "$footprint_total")"
    peak_mib="$(format_mib "$peak_total")"

    if [[ "$FORMAT" == "table" ]]; then
      printf '%-24s  %-18s  %5s  %10s  %14s  %14s  %8s\n' \
        "$timestamp" "$label" "$process_count" "$rss_mib" "$footprint_mib" "$peak_mib" "$cpu_total"
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$timestamp" "$label" "$process_count" "$rss_mib" "$footprint_mib" "$peak_mib" "$cpu_total"
    fi
  done
}

write_system_summary
print_header

sample=1
while [[ "$sample" -le "$COUNT" ]]; do
  capture_sample "$sample"
  if [[ "$sample" -lt "$COUNT" ]]; then
    "$SLEEP_CMD" "$INTERVAL"
  fi
  sample=$((sample + 1))
done
