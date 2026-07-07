---
name: use-dotfiles
description: Use n-dotfiles repository conventions for setup, Brewfile and mise tool management, macOS defaults, Stow trees, harness assets, and validation.
---

# Use n-dotfiles

Use this skill when working in the n-dotfiles repository.

## Workflow

1. Read `AGENTS.md` and `CONTEXT.md` before changing behavior.
2. Keep changes small, reviewable, and idempotent.
3. Treat Git as read-only unless the user explicitly asks for commits, pushes, or branches.
4. Prefer `--help` and `--dry-run` before mutating setup scripts.
5. Stop and ask before running commands likely to take more than about 5 minutes.

## Placement

- Cross-platform CLI tools and runtimes belong in `mise/.config/mise/config.toml` (check `mise registry <name>` for short names; use `github:owner/repo` otherwise).
- macOS casks, fonts, Mac App Store apps, and mac formulae belong in `Brewfile`; Linux formulae in `Brewfile.posix`.
- AI CLIs (claude, codex, opencode, copilot) stay unmanaged — do not add them to Brewfile or mise.
- macOS setting changes belong in `_macos/`.
- Dotfile content belongs in the matching Stow tree such as `zsh/`, `git/`, `nvim/`, or `kitty/`; register new trees in `STOW_DIRS` in `stow.sh`.
- Harness asset and skill guidance should use portable relative paths.

## Validation

Prefer the narrowest relevant validation first:

- `./stow.sh --list`
- `./stow.sh --dry-run`
- `./bootstrap.sh --dry-run --no-input --skip-1password`
- `./setup-personal-mac.sh --dry-run --no-input`
- `brew bundle list --file Brewfile` (parse check)
- `./_test/run_tests.sh`
- `./_test/shellcheck.sh`
