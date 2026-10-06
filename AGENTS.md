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

Arch/Omarchy skips layer 1 entirely: pacman (including its `mise` package)
owns system packages instead of Homebrew, so only `./stow.sh` and
`mise install` apply there. See [omarchy/README.md](omarchy/README.md).

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
- `./bootstrap.sh --dry-run --no-input --skip-1password` (macOS)
- `./bootstrap-omarchy.sh --dry-run --no-input` (Arch/Omarchy)
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

## Codex workflow

- Keep this file short, concrete, and repo-specific. Capture layout, commands, conventions, constraints, and done criteria; move repeatable procedures to scoped skills/docs.
- For each task, state the goal, relevant context/files, constraints, and verification criteria. Plan complex or ambiguous work before editing.
- Keep one thread per coherent outcome. Read only relevant files; delegate bounded exploration/tests when useful, and use worktrees for parallel work.
- Verify changes with focused tests and applicable lint, formatting, type checks, builds, and diff review; report checks run or skipped.
- Prefer least-privilege permissions and dry-runs. Add MCP/tools only when they remove a real repeated loop.
- Use background or scheduled work for long-running or recurring tasks instead of continuous polling.
- After a repeated mistake or correction, update this file with the smallest actionable rule that would prevent it.

Reference: [Codex best practices](https://learn.chatgpt.com/guides/best-practices)
