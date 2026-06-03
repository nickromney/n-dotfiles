#!/usr/bin/env bats
# Tests for repo-local agent harness guide references.

setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
}

referenced_repo_skills() {
  local guide

  for guide in AGENTS.md CLAUDE.md GEMINI.md; do
    if [ -f "$DOTFILES_DIR/$guide" ]; then
      grep -Eho 'skills/[A-Za-z0-9._/-]+' "$DOTFILES_DIR/$guide" 2>/dev/null \
        | sed 's#[).,;:]*$##'
    fi
  done | sort -u
}

@test "project harness guides: referenced repo-local skills exist" {
  local refs=()
  local ref
  local missing=()

  while IFS= read -r ref; do
    refs+=("$ref")
    if [ ! -f "$DOTFILES_DIR/$ref" ]; then
      missing+=("$ref")
    fi
  done < <(referenced_repo_skills)

  [ "${#refs[@]}" -gt 0 ]

  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'Missing referenced skills:\n' >&3
    printf '  %s\n' "${missing[@]}" >&3
    return 1
  fi
}

@test "project harness guides: referenced repo-local skills are trackable" {
  local ref
  local ignored=()

  while IFS= read -r ref; do
    if git -C "$DOTFILES_DIR" check-ignore -q -- "$ref"; then
      ignored+=("$ref")
    fi
  done < <(referenced_repo_skills)

  if [ "${#ignored[@]}" -gt 0 ]; then
    printf 'Ignored referenced skills:\n' >&3
    printf '  %s\n' "${ignored[@]}" >&3
    return 1
  fi
}
