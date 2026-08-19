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

Reconcile selected private harness assets into the public harness views. The default
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
      --execute             Reconcile links
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
  local name="$4"
  local dest_path
  local target
  local existing_target

  dest_path="$dest_dir/$name"
  target="$(relative_private_skill_target "$source_path" "$private_abs")"

  if [[ -n "${DESIRED_LINKS_FILE:-}" ]]; then
    printf '%s\n' "$dest_path" >>"$DESIRED_LINKS_FILE"
  fi

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

build_loaded_skill_index() {
  local index_file="$1"
  local view="$2"
  shift 2

  local catalog_dir
  local provider_dir
  local source_path
  local skill_name

  : >"$index_file"

  for catalog_dir in "$@"; do
    [[ -d "$catalog_dir" ]] || continue
    for provider_dir in "$catalog_dir"/*; do
      [[ -d "$provider_dir" ]] || continue
      [[ -d "$provider_dir/skills" ]] || continue

      for source_path in "$provider_dir/skills"/*; do
        [[ -e "$source_path" || -L "$source_path" ]] || continue
        [[ -f "$source_path/SKILL.md" ]] || continue
        skill_name="$(basename "$source_path")"
        if skill_is_loaded_for_view "$provider_dir" "$skill_name" "$view"; then
          printf '%s\t%s\n' "$skill_name" "$(basename "$provider_dir")" >>"$index_file"
        fi
      done
    done
  done
}

skill_name_has_loaded_collision() {
  local skill_name="$1"

  awk -F '\t' -v wanted="$skill_name" \
    '$1 == wanted { providers[$2] = 1 } END { count = 0; for (provider in providers) count++; exit !(count > 1) }' \
    "$LOADED_SKILL_INDEX_FILE"
}

link_skills_from_provider_dir() {
  local provider_dir="$1"
  local skills_dir
  local dest_dir="$2"
  local private_abs="$3"
  local view="$4"
  local source_path
  local skill_name
  local provider_name
  local destination_name
  local found=false

  skills_dir="$provider_dir/skills"
  [[ -d "$skills_dir" ]] || return 0
  mkdir -p "$dest_dir"
  provider_name="$(basename "$provider_dir")"

  for source_path in "$skills_dir"/*; do
    [[ -e "$source_path" || -L "$source_path" ]] || continue
    [[ -f "$source_path/SKILL.md" ]] || continue
    skill_name="$(basename "$source_path")"
    if ! skill_is_loaded_for_view "$provider_dir" "$skill_name" "$view"; then
      continue
    fi
    found=true
    destination_name="$skill_name"
    if skill_name_has_loaded_collision "$skill_name"; then
      destination_name="${provider_name}-${skill_name}"
      info "namespaced collision $skill_name as $destination_name"
    fi
    link_skill "$(absolute_path "$source_path")" "$dest_dir" "$private_abs" "$destination_name"
  done

  if [[ "$found" != "true" ]]; then
    info "no loaded skills found in $skills_dir for $view"
  fi
}

resolve_link_target() {
  local link_path="$1"
  local target

  target="$(readlink "$link_path")"
  if [[ "$target" = /* ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  (
    cd "$(dirname "$link_path")"
    cd "$(dirname "$target")"
    printf '%s/%s\n' "$(pwd)" "$(basename "$target")"
  )
}

prune_stale_private_links() {
  local dest_dir="$1"
  local private_abs="$2"
  local dest_path
  local source_path

  [[ -d "$dest_dir" ]] || return 0

  for dest_path in "$dest_dir"/*; do
    [[ -L "$dest_path" ]] || continue
    source_path="$(resolve_link_target "$dest_path")" || continue
    case "$source_path" in
      "$private_abs"/*)
        if ! grep -Fqx "$dest_path" "$DESIRED_LINKS_FILE"; then
          if [[ "$DRY_RUN" == "true" ]]; then
            info "would remove stale $dest_path"
          else
            rm "$dest_path"
            info "removed stale $dest_path"
          fi
        fi
        ;;
    esac
  done
}

sync_view() {
  local dest_dir="$1"
  local private_abs="$2"
  local view="$3"
  shift 3

  DESIRED_LINKS_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-private-skills.XXXXXX")"
  LOADED_SKILL_INDEX_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-private-index.XXXXXX")"

  build_loaded_skill_index "$LOADED_SKILL_INDEX_FILE" "$view" "$@"

  local catalog_dir
  for catalog_dir in "$@"; do
    link_grouped_skills_from "$catalog_dir" "$dest_dir" "$private_abs" "$view"
  done

  prune_stale_private_links "$dest_dir" "$private_abs"
  rm -f "$DESIRED_LINKS_FILE" "$LOADED_SKILL_INDEX_FILE"
  DESIRED_LINKS_FILE=""
  LOADED_SKILL_INDEX_FILE=""
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

  sync_view "$agents_skills" "$private_abs" "global" "$private_abs"
  sync_view "$claude_skills" "$private_abs" "claude" "$private_abs" "$private_abs/claude"
  sync_view "$codex_skills" "$private_abs" "codex" "$private_abs" "$private_abs/codex"
}

main "$@"
