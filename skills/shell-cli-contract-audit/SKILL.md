---
name: shell-cli-contract-audit
description: >
  Audit shell-script CLI contracts for agent-friendly behavior: non-interactive
  execution, useful --help output with examples, named flags over positional-only
  inputs, --dry-run on mutating commands, and explicit confirmation bypass flags.
  Use when reviewing or improving bash/zsh installer, setup, or maintenance scripts.
---

# Shell CLI Contract Audit

Audit shell entrypoints against an agent-friendly CLI contract. The baseline is:

- Every meaningful entrypoint has `-h/--help`
- Help includes examples, not just prose
- Interactive prompts have a flag-based escape hatch
- Mutating flows support `--dry-run`
- Important inputs can be supplied as named flags, not only positional arguments
- Error paths are actionable and point at the correct invocation

## Use This Skill When

- Reviewing setup/install/update scripts for automation safety
- Tightening a public dotfiles repo so humans and agents can both drive it
- Comparing existing shell entrypoints against a consistent CLI disclosure rubric

## Workflow

1. Run `./skills/shell-cli-contract-audit/scripts/audit-shell-cli-contracts.sh`.
2. Read the flagged files directly before suggesting edits; the scanner is heuristic, not authoritative.
3. Prioritize entrypoints that mutate the host machine or gate the main setup flow.
4. Prefer small interface fixes over sweeping rewrites.

## Audit Script

The bundled script scans shell entrypoints and reports whether they expose:

- help output
- examples
- `--dry-run`
- interactive prompts
- non-interactive escape flags such as `--yes`, `--force`, or `--no-input`
- flag parsing versus positional-only contracts

Useful invocations:

```bash
./skills/shell-cli-contract-audit/scripts/audit-shell-cli-contracts.sh
./skills/shell-cli-contract-audit/scripts/audit-shell-cli-contracts.sh --format tsv
./skills/shell-cli-contract-audit/scripts/audit-shell-cli-contracts.sh --all --include-skills
./skills/shell-cli-contract-audit/scripts/audit-shell-cli-contracts.sh scripts/
```

## Review Rules

- Treat top-level setup/install scripts as highest priority.
- Internal helper scripts can stay positional if they are clearly not user-facing, but call that out explicitly.
- If a script prompts, suggest the missing flag contract before suggesting UI tweaks.
- If a script mutates state and lacks `--dry-run`, treat that as a contract gap unless it is obviously a private helper.
