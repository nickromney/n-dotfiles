# Agent Guide (n-dotfiles)

Use this file as a map, not a manual.

## Core Rules

- Keep changes small, reviewable, and idempotent.
- Git is read-only unless the user explicitly asks for commits, pushes, or branches.
- No destructive operations without explicit approval.
- Prefer `--help` and `--dry-run` before mutating setup scripts.
- If a command is likely to run for more than about 5 minutes, stop and ask.

## Repo Map

- `_configs/` contains YAML bundles consumed by `install.sh` and the Makefile.
- `_macos/` contains macOS defaults logic and per-profile YAML.
- `_test/` contains Bats suites, mocks, and runners.
- App directories such as `zsh/`, `git/`, `nvim/`, and `kitty/` are GNU Stow trees.

## Preferred Commands

- `./install.sh --help`
- `./install.sh --list`
- `./bootstrap.sh --dry-run --no-input --skip-1password`
- `./setup-personal-mac.sh --dry-run --no-input`
- `./_test/run_tests.sh`
- `./_test/shellcheck.sh`

## Change Rules

- Tool install definitions belong in `_configs/*.yaml`.
- macOS setting changes belong in `_macos/`, not manual machine state.
- Dotfile content belongs in the matching Stow directory.
- User-facing shell entrypoints should keep `--help`, examples, `--dry-run` when mutating, and explicit non-interactive escapes for prompts.
- Repo docs and skills should use portable relative paths, not machine-specific absolute repo-root paths.

## More Context

- Use [skills/use-dotfiles/SKILL.md](skills/use-dotfiles/SKILL.md) for repo-specific workflows and validation guidance.
- Use [skills/shell-cli-contract-audit/SKILL.md](skills/shell-cli-contract-audit/SKILL.md) when changing setup or maintenance CLIs.
