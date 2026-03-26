---
name: use-dotfiles
description: >
  Use when working in this n-dotfiles repo: shell installers, config bundles,
  macOS defaults, GNU Stow trees, 1Password setup helpers, or test/validation
  flows. Covers where behavior lives, preferred commands, validation, and the
  repo's agent-friendly CLI expectations.
---

# Use Dotfiles

Use this skill when the task is specific to this repo's setup, install, macOS,
Stow, or shell-script workflow.

## Repo Mental Model

- `_configs/` is the source of truth for installable tools.
- `_macos/` is the source of truth for macOS defaults and profile-specific settings.
- App directories such as `zsh/`, `git/`, `nvim/`, `tmux/`, and `kitty/` are Stow trees that mirror final paths under `$HOME`.
- `_test/` contains Bats suites and helpers. Prefer mocks over touching host state.
- `install.sh` is the main public installer; most install logic lives in `scripts/install-lib.sh`.
- `bootstrap.sh`, `setup-personal-mac.sh`, `setup-work-mac.sh`, and the 1Password scripts are user-facing entrypoints and should stay automation-safe.

## Prefer These Commands

```bash
./install.sh --help
./install.sh --list
./install.sh -d
./bootstrap.sh --dry-run --no-input --skip-1password
./setup-personal-mac.sh --dry-run --no-input
./setup-work-mac.sh --dry-run --no-input
./_test/run_tests.sh
./_test/shellcheck.sh
./skills/shell-cli-contract-audit/scripts/audit-shell-cli-contracts.sh --format tsv .
```

Use `make` when there is already a target for the workflow; otherwise call the
script directly.

## Where To Change Things

### Add or modify installed tools

- Edit the relevant YAML in `_configs/shared/`, `_configs/host/`, or `_configs/focus/`.
- Keep install definitions declarative there instead of hardcoding tool installs in wrapper scripts.
- Validate with `./install.sh --list` and targeted install/dry-run commands.

### Change setup or maintenance CLIs

- Keep top-level entrypoints non-interactive by defaulting prompts behind explicit flags.
- Mutating scripts should expose `--dry-run`.
- Help output should include examples.
- If the script prompts, it should also expose `--no-input`, `--yes`, `--force`, or an equivalent escape hatch.
- Run the shell CLI audit skill after changes.

### Change macOS behavior

- Prefer `_macos/*.yaml` for profile values.
- Change `_macos/macos.sh` only when the settings engine or CLI contract needs to change.
- Keep `_macos/macos.sh --no-input` usable in automation.

### Change dotfiles or app config

- Edit the matching Stow directory directly.
- Do not patch symlink targets under `$HOME`; change the tracked source files instead.

### Change 1Password-backed setup

- Keep safe mode the default.
- Private-key or credential download paths need explicit confirmation/bypass flags.
- Do not add secrets to the repo.

## Validation

Prefer targeted validation while iterating:

- `cd _test && bats install.bats`
- `cd _test && bats macos.bats`
- `cd _test && bats 1password.bats`
- `cd _test && bats setup-personal-mac.bats`
- `cd _test && bats setup-work-mac.bats`

Run the full gate before finishing broader changes:

```bash
./_test/run_tests.sh
./_test/shellcheck.sh
```

When changing user-facing shell entrypoints, also run:

```bash
./skills/shell-cli-contract-audit/scripts/audit-shell-cli-contracts.sh --format tsv .
```

## Repo-Specific Expectations

- Keep shell changes idempotent.
- Fix root causes instead of suppressing warnings or skipping validation.
- Avoid repo-wide scripted rewrites unless the user explicitly wants one.
- Keep always-loaded instructions short; move deeper repo process into skills or repo docs.

## Related Skills

- Use [skills/shell-cli-contract-audit/SKILL.md](../shell-cli-contract-audit/SKILL.md) when hardening shell entrypoints.
- Use [skills/fix-markdown/SKILL.md](../fix-markdown/SKILL.md) when a task is mostly Markdown cleanup or markdownlint remediation.
