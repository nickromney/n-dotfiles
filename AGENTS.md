# Repository Guidelines

## Project Structure & Module Organization

- `_configs/` holds YAML bundles (shared, host, focus) that feed `install.sh` and Makefile profiles.
- `_macos/` contains `macos.sh` plus per-profile YAML; update settings here rather than editing macOS manually.
- `_test/` stores Bats suites, helpers, and meta-runners (`run_tests.sh`, `shellcheck.sh`).
- Tool directories (`nvim/`, `kitty/`, `aws/`, `tmux/`, `zsh/`, etc.) mirror their target paths for GNU Stow; add new folders to `STOW_DIRS`.

## Build, Test, and Development Commands

- `./bootstrap.sh` — prepare a fresh macOS host with Homebrew, Stow, and baseline packages.
- `./install.sh [-d|-s|-u]` — core installer; dry-run with `-d`, stow configs via `-s`, and update installed tools with `-u`.
- `make common|personal|work install` — run Makefile bundles; override the VS Code CLI with `VSCODE_CLI=cursor make focus-vscode`.
- `make focus-mas install` — optional Mac App Store apps (run after signing in and clicking “Get” so `mas install` can succeed).
- `make test` or `_test/run_tests.sh` — execute the full Bats matrix.
- `make precommit` — run all pre-commit hooks before pushing.

## Coding Style & Naming Conventions

- All scripts are Bash with `set -euo pipefail`, two-space indenting, snake_case functions, and `[[ … ]]` tests.
- Keep logic idempotent and guard every external dependency (see `REQUIRED_COMMANDS` and `get_available_managers` in `install.sh`).
- Run `_test/shellcheck.sh` after touching shell code; prefer fixing lint findings over shellcheck disables.
- Stow payloads must mimic the final filesystem layout (e.g., `nvim/.config/nvim/init.lua`).

## Testing Guidelines

- Tests live in `_test/*.bats` and should mock host commands through `_test/helpers` rather than altering the real OS.
- Use targeted runners when iterating: `_test/run_install_tests.sh` for installer logic, `_test/run_macos_tests.sh` for system defaults.
- Call out any manual verification (for example `./_macos/macos.sh -d personal.yaml`) in your PR description when automation cannot cover it.

## Commit & Pull Request Guidelines

- Follow the Conventional Commit pattern already in git history (`feat:`, `chore:`, `docs:`) and keep summaries under ~70 characters.
- Describe which config bundles are affected, list the commands you ran (`make test`, `./install.sh -d -s`), and mention host prerequisites (Homebrew, 1Password vaults, tokens).
- Reference issues and link screenshots if UI-facing dotfiles (Ghostty, Kitty, VS Code) change behavior.
- Avoid bundling unrelated changes; small, reviewable diffs make it easier to test across macOS and dev containers.

## Security & Configuration Tips

- Secrets never belong in dotfiles; use the 1Password-backed helpers (`setup-ssh-from-1password.sh`, `setup-gitconfig-from-1password.sh`) and document any new items they require.
- When introducing new package managers or credentials, update `REQUIRED_COMMANDS`, dry-run handling, and docs so contributors without sudo can still run `./install.sh -d` safely.
