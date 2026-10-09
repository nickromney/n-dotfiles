#!/usr/bin/env bats

setup() {
  FIXTURE_ROOT="$(mktemp -d)"
  DOTFILES_ROOT="$FIXTURE_ROOT/n-dotfiles"
  PRIVATE_ROOT="$FIXTURE_ROOT/harnesses-private"
  mkdir -p "$DOTFILES_ROOT/scripts" "$PRIVATE_ROOT"
  cp "$BATS_TEST_DIRNAME/../scripts/sync-private-harness-assets.sh" "$DOTFILES_ROOT/scripts/"
}

teardown() {
  rm -rf "$FIXTURE_ROOT"
}

make_skill() {
  local provider="$1" name="$2"
  mkdir -p "$PRIVATE_ROOT/$provider/skills/$name"
  printf '# Fixture\n' > "$PRIVATE_ROOT/$provider/skills/$name/SKILL.md"
}

@test "pstack selections reach shared Claude and Codex views without loading unselected principles" {
  make_skill pstack poteto-mode
  make_skill pstack principle-testing
  mkdir -p "$PRIVATE_ROOT/pstack/load"
  printf 'poteto-mode\n' > "$PRIVATE_ROOT/pstack/load/global.txt"

  run bash "$DOTFILES_ROOT/scripts/sync-private-harness-assets.sh" --execute --private-root "$PRIVATE_ROOT"
  [ "$status" -eq 0 ]
  for view in agents/.agents/skills claude/.claude/skills codex/.codex/skills; do
    [ -f "$DOTFILES_ROOT/$view/poteto-mode/SKILL.md" ]
    [ ! -L "$DOTFILES_ROOT/$view/principle-testing" ]
  done
}

@test "pstack collisions are namespaced and unrelated Codex skills survive reconciliation" {
  make_skill pstack tdd
  make_skill mattpocock tdd
  mkdir -p "$DOTFILES_ROOT/codex/.codex/skills/local-only"
  printf '# Local\n' > "$DOTFILES_ROOT/codex/.codex/skills/local-only/SKILL.md"

  run bash "$DOTFILES_ROOT/scripts/sync-private-harness-assets.sh" --execute --private-root "$PRIVATE_ROOT"
  [ "$status" -eq 0 ]
  for view in agents/.agents/skills claude/.claude/skills codex/.codex/skills; do
    [ -f "$DOTFILES_ROOT/$view/pstack-tdd/SKILL.md" ]
    [ -f "$DOTFILES_ROOT/$view/mattpocock-tdd/SKILL.md" ]
    [ ! -L "$DOTFILES_ROOT/$view/tdd" ]
  done
  [ -f "$DOTFILES_ROOT/codex/.codex/skills/local-only/SKILL.md" ]

  run bash "$DOTFILES_ROOT/scripts/sync-private-harness-assets.sh" --execute --private-root "$PRIVATE_ROOT"
  [ "$status" -eq 0 ]
  [ -f "$DOTFILES_ROOT/codex/.codex/skills/local-only/SKILL.md" ]
}
