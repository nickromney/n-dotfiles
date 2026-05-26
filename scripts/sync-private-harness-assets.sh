#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_ROOT="${PRIVATE_HARNESSES_ROOT:-$(cd "$REPO_ROOT/.." && pwd)/harnesses-private}"
DRY_RUN=false
EXECUTE=false

usage() {
  local exit_code=${1:-0}

  cat <<'EOF'
Usage: scripts/sync-private-harness-assets.sh [options] [--dry-run|--execute]

Link selected private harness assets into the public harness views. The default
private source is the optional sibling repo ../harnesses-private. If that repo
is absent, the script exits successfully without changing anything.

Skill sources are discovered one provider level deep, for example:
  ../harnesses-private/mattpocock/skills/tdd
  ../harnesses-private/joshpigford/skills/example
  ../harnesses-private/agents/skills/use-platform

If a provider has load manifests, only listed skills are exposed:
  <provider>/load/global.txt
  <provider>/load/claude.txt
  <provider>/load/codex.txt

Options:
      --dry-run             Show planned links without changing files
      --execute             Create missing links
  -h, --help                Show this help message
      --private-root <path> Private harness repository path

Examples:
  scripts/sync-private-harness-assets.sh --dry-run
  scripts/sync-private-harness-assets.sh --execute
  scripts/sync-private-harness-assets.sh --dry-run --private-root ../harnesses-private
EOF

  exit "$exit_code"
}

error() {
  echo "Error: $*" >&2
}

info() {
  echo "INFO $*"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --execute)
        EXECUTE=true
        shift
        ;;
      -h|--help)
        usage 0
        ;;
      --private-root)
        if [[ -n "${2:-}" && "$2" != -* ]]; then
          PRIVATE_ROOT="$2"
          shift 2
        else
          error "--private-root requires a path"
          usage 1
        fi
        ;;
      --private-root=*)
        PRIVATE_ROOT="${1#*=}"
        shift
        ;;
      *)
        error "Unknown option: $1"
        usage 1
        ;;
    esac
  done

  if [[ "$DRY_RUN" == "true" && "$EXECUTE" == "true" ]]; then
    error "--dry-run and --execute cannot be combined"
    usage 1
  fi

  if [[ "$DRY_RUN" != "true" && "$EXECUTE" != "true" ]]; then
    error "Choose --dry-run or --execute"
    usage 1
  fi
}

absolute_path() {
  local path="$1"
  local dir
  local base

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    (cd "$dir" && printf '%s/%s\n' "$(pwd)" "$base")
  fi
}

relative_private_skill_target() {
  local source_path="$1"
  local private_abs="$2"

  case "$source_path" in
    "$private_abs"/*)
      printf '../../../../harnesses-private/%s\n' "${source_path#"$private_abs"/}"
      ;;
    *)
      printf '%s\n' "$source_path"
      ;;
  esac
}

link_skill() {
  local source_path="$1"
  local dest_dir="$2"
  local private_abs="$3"
  local name
  local dest_path
  local target
  local existing_target

  name="$(basename "$source_path")"
  dest_path="$dest_dir/$name"
  target="$(relative_private_skill_target "$source_path" "$private_abs")"

  if [[ -L "$dest_path" ]]; then
    existing_target="$(readlink "$dest_path")"
    if [[ "$existing_target" == "$target" ]]; then
      info "ok $dest_path -> $target"
      return 0
    fi
    error "Conflict: $dest_path points to $existing_target, expected $target"
    return 1
  fi

  if [[ -e "$dest_path" ]]; then
    error "Conflict: $dest_path exists and is not a symlink"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "would link $dest_path -> $target"
  else
    ln -s "$target" "$dest_path"
    info "linked $dest_path -> $target"
  fi
}

manifest_has_skill() {
  local manifest="$1"
  local skill_name="$2"
  local line

  [[ -f "$manifest" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line//$'\t'/ }"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    [[ "$line" == "$skill_name" ]] && return 0
  done < "$manifest"

  return 1
}

provider_has_load_manifests() {
  local provider_dir="$1"
  [[ -f "$provider_dir/load/global.txt" || -f "$provider_dir/load/claude.txt" || -f "$provider_dir/load/codex.txt" ]]
}

skill_is_loaded_for_view() {
  local provider_dir="$1"
  local skill_name="$2"
  local view="$3"

  if ! provider_has_load_manifests "$provider_dir"; then
    return 0
  fi

  manifest_has_skill "$provider_dir/load/global.txt" "$skill_name" && return 0
  manifest_has_skill "$provider_dir/load/$view.txt" "$skill_name" && return 0

  return 1
}

link_skills_from_provider_dir() {
  local provider_dir="$1"
  local skills_dir
  local dest_dir="$2"
  local private_abs="$3"
  local view="$4"
  local source_path
  local skill_name
  local found=false

  skills_dir="$provider_dir/skills"
  [[ -d "$skills_dir" ]] || return 0
  mkdir -p "$dest_dir"

  for source_path in "$skills_dir"/*; do
    [[ -e "$source_path" || -L "$source_path" ]] || continue
    [[ -f "$source_path/SKILL.md" ]] || continue
    skill_name="$(basename "$source_path")"
    if ! skill_is_loaded_for_view "$provider_dir" "$skill_name" "$view"; then
      continue
    fi
    found=true
    link_skill "$(absolute_path "$source_path")" "$dest_dir" "$private_abs"
  done

  if [[ "$found" != "true" ]]; then
    info "no loaded skills found in $skills_dir for $view"
  fi
}

link_grouped_skills_from() {
  local catalog_dir="$1"
  local dest_dir="$2"
  local private_abs="$3"
  local view="$4"
  local provider_dir
  local reserved_name

  [[ -d "$catalog_dir" ]] || return 0

  for provider_dir in "$catalog_dir"/*; do
    [[ -d "$provider_dir" ]] || continue

    reserved_name="$(basename "$provider_dir")"
    case "$reserved_name" in
      .git|scripts|sources)
        continue
        ;;
    esac

    link_skills_from_provider_dir "$provider_dir" "$dest_dir" "$private_abs" "$view"
  done
}

main() {
  local private_abs
  local agents_skills="$REPO_ROOT/agents/.agents/skills"
  local claude_skills="$REPO_ROOT/claude/.claude/skills"
  local codex_skills="$REPO_ROOT/codex/.codex/skills"

  parse_args "$@"

  if [[ ! -d "$PRIVATE_ROOT" ]]; then
    info "optional private source not found: $PRIVATE_ROOT"
    exit 0
  fi

  private_abs="$(absolute_path "$PRIVATE_ROOT")"

  link_grouped_skills_from "$private_abs" "$agents_skills" "$private_abs" "global"
  link_grouped_skills_from "$private_abs" "$claude_skills" "$private_abs" "claude"
  link_grouped_skills_from "$private_abs" "$codex_skills" "$private_abs" "codex"
  link_grouped_skills_from "$private_abs/claude" "$claude_skills" "$private_abs" "claude"
  link_grouped_skills_from "$private_abs/codex" "$codex_skills" "$private_abs" "codex"
}

main "$@"
