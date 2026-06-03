---
name: shell-cli-contract-audit
description: Audit n-dotfiles shell entrypoints for help text, dry-run safety, non-interactive behavior, argument parsing, and validation coverage.
---

# Shell CLI Contract Audit

Use this skill when changing setup or maintenance shell entrypoints.

## Contract

User-facing shell entrypoints should:

- Expose `--help` with examples.
- Support `--dry-run` when they mutate machine state.
- Provide explicit non-interactive escapes for prompts, usually `--no-input`.
- Reject unknown options with a clear error and non-zero exit.
- Avoid destructive operations without explicit approval.
- Keep behavior idempotent when re-run.

## Review Steps

1. Read the entrypoint and any sourced library it delegates to.
2. Check that mutating paths have a dry-run or safe preview mode.
3. Check prompts and non-interactive execution paths.
4. Check argument validation for missing option values and conflicting flags.
5. Add or update Bats tests through the public command interface.
6. Run focused Bats tests, then `./_test/shellcheck.sh`.

## Related Tests

- `_test/cli-contracts.bats`
- `_test/bootstrap.bats`
- `_test/install.bats`
- `_test/setup-personal-mac.bats`
- `_test/setup-work-mac.bats`
- `_test/1password.bats`
