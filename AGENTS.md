# Agent Guide (n-dotfiles)

Use this file as a map, not a manual.

## Core Rules

- Keep changes small, reviewable, and idempotent.
- Git is read-only unless the user explicitly asks for commits, pushes, or branches.
- No destructive operations without explicit approval.
- Prefer `--help` and `--dry-run` before mutating setup scripts.
- If a command is likely to run for more than about 5 minutes, stop and ask.

## Architecture

Machine setup is three declarative layers, each applied by a tool this
repo does not implement:

1. `brew bundle` — `Brewfile` (macOS casks, fonts, mas apps, formulae); `Brewfile.posix` on Linux.
2. `stow` — dotfile symlinks via `./stow.sh`.
3. `mise install` — CLI tools and runtimes from `mise/.config/mise/config.toml` (stowed to `~/.config/mise/`).

AI CLIs (claude, codex, opencode, copilot) are deliberately unmanaged;
their native installers own updates.

## Repo Map

- `Brewfile` / `Brewfile.posix` are hand-maintained (no generator).
- `mise/` is the Stow tree for the global mise config.
- `_macos/` contains macOS defaults logic and per-profile YAML.
- `_test/` contains Bats suites, mocks, and runners.
- App directories such as `zsh/`, `git/`, `nvim/`, and `kitty/` are GNU Stow trees.

## Preferred Commands

- `./stow.sh --list` and `./stow.sh --dry-run`
- `./bootstrap.sh --dry-run --no-input --skip-1password`
- `./setup-personal-mac.sh --dry-run --no-input`
- `make help`
- `./_test/run_tests.sh`
- `./_test/shellcheck.sh`

## Change Rules

- Cross-platform CLI tools belong in `mise/.config/mise/config.toml`.
- macOS apps, casks, fonts, and mas entries belong in `Brewfile`.
- macOS setting changes belong in `_macos/`, not manual machine state.
- Dotfile content belongs in the matching Stow directory; new Stow packages must be added to `STOW_DIRS` in `stow.sh`.
- User-facing shell entrypoints should keep `--help`, examples, `--dry-run` when mutating, and explicit non-interactive escapes for prompts.
- Repo docs and skills should use portable relative paths, not machine-specific absolute repo-root paths.

## More Context

- Use [skills/use-dotfiles/SKILL.md](skills/use-dotfiles/SKILL.md) for repo-specific workflows and validation guidance.
- Use [skills/shell-cli-contract-audit/SKILL.md](skills/shell-cli-contract-audit/SKILL.md) when changing setup or maintenance CLIs.
