#!/usr/bin/env bash
# Verify n-dotfiles by applying one real Stow package in an isolated home.
# Bash 3.2 compatible.
# shellcheck disable=SC2034 # VK_* settings are read by the sourced verify-lib.sh
set -euo pipefail

VK_SCRIPT="$0"
VK_APP="n-dotfiles"
VK_DESCRIPTION="Verify n-dotfiles package discovery and Git configuration stowing in a temporary home."
# shellcheck source=verify-lib.sh disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/verify-lib.sh"

vk_commands_help() {
  cat <<'HELP'
  launch                 create an isolated home for this run
  doctor                 check GNU Stow and the isolated home
  stow-git               stow the Git package and inspect its user-facing config
  cleanup                remove this run's state; keep evidence
HELP
}
vk_sample_commands() { printf '%s\n' verify launch doctor stow-git cleanup; }
vk_paths() {
  STATE="$VK_BASE_DIR/$VK_RUN_ID/state"
  VERIFY_HOME="$STATE/home"
  EVIDENCE="$VK_EVIDENCE_ROOT/$VK_RUN_ID"
}

vk_plan() {
  case "$1" in
    verify) vk_plan_line "create isolated HOME, check GNU Stow, apply git package, assert ~/.gitconfig, clean state; keep evidence in $EVIDENCE" ;;
    launch) vk_plan_line "create $VERIFY_HOME and record this checkout in $EVIDENCE" ;;
    doctor) vk_plan_line "check GNU Stow and confirm the isolated home exists under $STATE" ;;
    stow-git) vk_plan_line "run stow.sh git with scoped HOME=$VERIFY_HOME and assert ~/.gitconfig content" ;;
    cleanup) vk_plan_line "remove $STATE; keep $EVIDENCE" ;;
    *) vk_unknown_command ;;
  esac
}

cmd_launch() {
  mkdir -p "$VERIFY_HOME" "$EVIDENCE"
  vk_mark_current
  vk_record_revision "$EVIDENCE/revision.txt"
  vk_say "ready run=$VK_RUN_ID home=$VERIFY_HOME evidence=$EVIDENCE"
}

cmd_doctor() {
  [ -d "$VERIFY_HOME" ] || { vk_fail "isolated home is missing; launch first"; return 1; }
  command -v stow >/dev/null 2>&1 || { vk_fail "GNU Stow is required"; return 1; }
  stow --version > "$EVIDENCE/stow-version.txt"
  vk_say "OK GNU Stow available; isolated home=$VERIFY_HOME"
}

cmd_stow_git() {
  cmd_doctor >/dev/null
  env HOME="$VERIFY_HOME" "$VK_ROOT/stow.sh" git > "$EVIDENCE/stow-git.log" 2>&1
  [ -L "$VERIFY_HOME/.gitconfig" ] || { vk_fail "Stow did not create ~/.gitconfig symlink"; return 1; }
  vk_expect_contains "$VERIFY_HOME/.gitconfig" '[user]'
  vk_expect_contains "$VERIFY_HOME/.gitconfig" 'name = Nick Romney'
  vk_expect_contains "$VERIFY_HOME/.gitconfig" '[alias]'
  cp "$VERIFY_HOME/.gitconfig" "$EVIDENCE/gitconfig-readback"
  vk_say "Stowed git package into isolated HOME=$VERIFY_HOME"
}

cmd_cleanup() {
  rm -rf "${STATE:?}"
  rmdir "$VK_BASE_DIR/$VK_RUN_ID" 2>/dev/null || true
  vk_clear_current
  vk_say "removed isolated home for run=$VK_RUN_ID; evidence kept at $EVIDENCE"
}

vk_verify_recipes() { cmd_stow_git; }

vk_dispatch() {
  local cmd="$1"
  shift
  case "$cmd" in
    launch) cmd_launch ;;
    doctor) cmd_doctor ;;
    stow-git) cmd_stow_git ;;
    cleanup) cmd_cleanup ;;
    *) vk_unknown_command ;;
  esac
}

vk_main "$@"
