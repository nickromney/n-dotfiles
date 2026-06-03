---
name: use-dotfiles
description: Use n-dotfiles repository conventions for setup, package catalog, macOS defaults, Stow trees, harness assets, and validation.
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

- Tool install definitions belong in `_configs/*.yaml`.
- macOS setting changes belong in `_macos/`.
- Dotfile content belongs in the matching Stow tree such as `zsh/`, `git/`, `nvim/`, or `kitty/`.
- Harness asset and skill guidance should use portable relative paths.

## Validation

Prefer the narrowest relevant validation first:

- `./install.sh --help`
- `./install.sh --list`
- `./bootstrap.sh --dry-run --no-input --skip-1password`
- `./setup-personal-mac.sh --dry-run --no-input`
- `./_test/run_tests.sh`
- `./_test/shellcheck.sh`
