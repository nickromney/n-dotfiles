# Codex Agent Guide (n-dotfiles)

**Purpose**: Operate safely in this repo, follow house style, and keep changes minimal,
reviewable, and idempotent.

## Quick Rules

- Read this file before major decisions; re-skim if requirements change.
- Keep commands short-lived; if something runs >5 minutes, stop and ask.
- Git is read-only unless the user explicitly asks for commits, pushes, or branches.
- No destructive operations unless the user explicitly approves.
- Fix root causes, avoid bandaids. Remove dead code instead of leaving breadcrumbs.
- Use `trash` for deletes when available.

## Repo Map

- `_configs/`: YAML bundles (shared, host, focus) used by `install.sh` and Makefile profiles.
- `_macos/`: macOS defaults scripts + per-profile YAML; change settings here, not manually.
- `_test/`: Bats suites, helpers, and runners (`run_tests.sh`, `shellcheck.sh`).
- Tool dirs (`nvim/`, `kitty/`, `tmux/`, `zsh/`, etc.) mirror final paths for GNU Stow.

## Common Commands

- `./bootstrap.sh`: prepare a fresh macOS host (Homebrew, Stow, baseline packages).
- `./install.sh [-d|-s|-u]`: core installer (dry-run, stow, update tools).
- `make common|personal|work install`: run Makefile bundles.
- `make app-store install`: optional App Store apps (after signing in).
- `make test` or `_test/run_tests.sh`: full Bats matrix.
- `make precommit`: run all pre-commit hooks.

## Coding Style

- Bash scripts: `set -euo pipefail`, two-space indent, snake_case functions, `[[ ... ]]`.
- Keep logic idempotent; guard external dependencies (see `REQUIRED_COMMANDS`).
- Prefer `rg` for search; use `ast-grep` for AST-safe edits when it helps.
- Keep files reasonable in size; split large files rather than expanding past ~500 LOC.

## Testing

- Tests live in `_test/*.bats`; mock via `_test/helpers` rather than touching the host OS.
- Run `_test/shellcheck.sh` after shell edits; fix issues rather than silencing.
- Prefer targeted runners while iterating (`_test/run_install_tests.sh`, `_test/run_macos_tests.sh`).

## Workflow & Safety

- Use repo task runners: prefer `just` if present, otherwise the `Makefile`.
- If a new dependency is needed, research maintained options and confirm with the user.
- Secrets never belong in dotfiles; use the 1Password-backed setup scripts.
- When adding package managers or credentials, update `REQUIRED_COMMANDS`, dry-run handling,
  and docs so `./install.sh -d` stays safe without sudo.

## Git & PR Guidance

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`) under ~70 chars.
- Use `gh` for PR/CI info; avoid opening URLs.
- Keep changes small and focused; avoid repo-wide search/replace scripts.

## Communication

- Be terse; noun-phrases are fine. Avoid filler.
- Prefer dry, low-key humor only if it will land.
- If you are unsure, ask with short options rather than guessing.

## Tooling Notes

- Web search early when blocked; prefer official docs and current sources.
- MCP via `mcporter` is allowed; if it is not installed, use `npx mcporter <server>`.
