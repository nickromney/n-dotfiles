#!/usr/bin/env bash
set -euo pipefail

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: audit-shell-cli-contracts.sh [options] [path]

Scan shell-script CLI contracts for agent-friendly disclosure patterns.

Options:
  -a, --all                Include scripts with no flagged issues
  -f, --format <format>    Output format: text or tsv (default: text)
  -h, --help               Show this help message
      --include-skills     Include scripts under skills/
      --include-templates  Include scripts under templates/
      --include-tests      Include scripts under _test/

Examples:
  audit-shell-cli-contracts.sh
  audit-shell-cli-contracts.sh --format tsv
  audit-shell-cli-contracts.sh --all --include-skills .
  audit-shell-cli-contracts.sh scripts/
EOF

  exit "$exit_code"
}

TARGET="."
FORMAT="text"
SHOW_ALL=false
INCLUDE_SKILLS=false
INCLUDE_TEMPLATES=false
INCLUDE_TESTS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--all)
      SHOW_ALL=true
      shift
      ;;
    -f|--format)
      if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
        FORMAT="$2"
        shift 2
      else
        echo "Error: --format requires 'text' or 'tsv'" >&2
        usage 1
      fi
      ;;
    -h|--help)
      usage 0
      ;;
    --include-skills)
      INCLUDE_SKILLS=true
      shift
      ;;
    --include-templates)
      INCLUDE_TEMPLATES=true
      shift
      ;;
    --include-tests)
      INCLUDE_TESTS=true
      shift
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      usage 1
      ;;
    *)
      if [[ "$TARGET" != "." ]]; then
        echo "Error: Only one path may be provided" >&2
        usage 1
      fi
      TARGET="$1"
      shift
      ;;
  esac
done

case "$FORMAT" in
  text|tsv)
    ;;
  *)
    echo "Error: Unsupported format: $FORMAT" >&2
    usage 1
    ;;
esac

if [[ ! -e "$TARGET" ]]; then
  echo "Error: Path not found: $TARGET" >&2
  exit 1
fi

contains_pattern() {
  local pattern=$1
  local file=$2

  if command -v rg >/dev/null 2>&1; then
    rg -q -- "$pattern" "$file"
  else
    grep -Eq -- "$pattern" "$file"
  fi
}

is_shell_entrypoint() {
  local file=$1
  local first_line

  IFS= read -r first_line <"$file" || true
  [[ "$first_line" =~ ^#!.*((ba|z)?sh)([[:space:]]|$) ]]
}

is_excluded_helper() {
  local file=$1

  case "$file" in
    */scripts/install-lib.sh|*/scripts/kubectl-aliases.sh|*/scripts/setup-mac-lib.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

print_text_report() {
  local file=$1
  local help_flag=$2
  local examples=$3
  local dry_run=$4
  local interactive=$5
  local escape_flag=$6
  local flag_parser=$7
  local long_flags=$8
  local destructive=$9
  local issues=${10}

  printf '%s\n' "$file"
  printf '  help: %s\n' "$help_flag"
  printf '  examples: %s\n' "$examples"
  printf '  dry_run: %s\n' "$dry_run"
  printf '  interactive: %s\n' "$interactive"
  printf '  non_interactive_escape: %s\n' "$escape_flag"
  printf '  flag_parser: %s\n' "$flag_parser"
  printf '  long_flags: %s\n' "$long_flags"
  printf '  destructive: %s\n' "$destructive"
  printf '  issues: %s\n' "$issues"
  printf '\n'
}

print_tsv_header() {
  printf 'file\thelp\texamples\tdry_run\tinteractive\tnon_interactive_escape\tflag_parser\tlong_flags\tdestructive\tissues\n'
}

find_args=("$TARGET" -type f -name '*.sh')
find_args+=("!" "-path" "*/.git/*")
find_args+=("!" "-path" "*/.git-hooks/*")
find_args+=("!" "-path" "*/node_modules/*")
find_args+=("!" "-path" "*/_reference/*")

if [[ "$INCLUDE_SKILLS" != "true" ]]; then
  find_args+=("!" "-path" "*/skills/*")
fi

if [[ "$INCLUDE_TEMPLATES" != "true" ]]; then
  find_args+=("!" "-path" "*/templates/*")
fi

if [[ "$INCLUDE_TESTS" != "true" ]]; then
  find_args+=("!" "-path" "*/_test/*")
fi

mapfile -t script_files < <(find "${find_args[@]}" | sort)

if [[ "$FORMAT" == "tsv" ]]; then
  print_tsv_header
fi

for file in "${script_files[@]}"; do
  if ! is_shell_entrypoint "$file"; then
    continue
  fi

  if is_excluded_helper "$file"; then
    continue
  fi

  help_flag="no"
  examples="no"
  dry_run="no"
  interactive="no"
  escape_flag="no"
  flag_parser="no"
  long_flags="no"
  destructive="no"
  issues=()

  contains_pattern '(^usage\(\)|Usage:|--help)' "$file" && help_flag="yes" || true
  contains_pattern 'Examples?:' "$file" && examples="yes" || true
  contains_pattern '--dry-run' "$file" && dry_run="yes" || true
  contains_pattern 'read .* -p|read -p|select |fzf|gum ' "$file" && interactive="yes" || true
  contains_pattern '--yes|--force|--unsafe|--no-input' "$file" && escape_flag="yes" || true
  contains_pattern 'getopts|while \[\[ \$# -gt 0 \]\]|case \$1 in' "$file" && flag_parser="yes" || true
  contains_pattern '--[a-z0-9][a-z0-9-]*' "$file" && long_flags="yes" || true
  contains_pattern 'rm -rf|rm -f|brew install|brew bundle|apt-get install|mas install|stow|defaults write|curl -fsSL' "$file" && destructive="yes" || true

  if [[ "$help_flag" != "yes" ]]; then
    issues+=("missing -h/--help")
  fi

  if [[ "$examples" != "yes" && "$help_flag" == "yes" ]]; then
    issues+=("help lacks examples")
  fi

  if [[ "$interactive" == "yes" && "$escape_flag" != "yes" ]]; then
    issues+=("interactive prompt lacks non-interactive escape flag")
  fi

  if [[ "$destructive" == "yes" && "$dry_run" != "yes" ]]; then
    issues+=("mutating flow lacks --dry-run")
  fi

  if [[ "$flag_parser" != "yes" && "$long_flags" != "yes" && "$destructive" == "yes" ]]; then
    issues+=("likely positional-only contract on a mutating script")
  fi

  if [[ ${#issues[@]} -eq 0 && "$SHOW_ALL" != "true" ]]; then
    continue
  fi

  issue_text="none"
  if [[ ${#issues[@]} -gt 0 ]]; then
    issue_text=$(IFS='; '; printf '%s' "${issues[*]}")
  fi

  if [[ "$FORMAT" == "tsv" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$file" \
      "$help_flag" \
      "$examples" \
      "$dry_run" \
      "$interactive" \
      "$escape_flag" \
      "$flag_parser" \
      "$long_flags" \
      "$destructive" \
      "$issue_text"
  else
    print_text_report \
      "$file" \
      "$help_flag" \
      "$examples" \
      "$dry_run" \
      "$interactive" \
      "$escape_flag" \
      "$flag_parser" \
      "$long_flags" \
      "$destructive" \
      "$issue_text"
  fi
done
