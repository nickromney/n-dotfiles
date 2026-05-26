# Harnesses

This directory records the intended source layout for portable agent harness
configuration. It does not currently install or reset live harness state.

## Model

- `shared/` is the public source for harness assets that can be reused across
  Claude Code, Codex, Gemini, OpenCode, and similar tools.
- Harness-specific directories are only for assets that need a different format
  or behavior for one harness.
- Private or paid assets live outside this public repo, by default in a sibling
  `../harnesses-private` repository.
- Setup must tolerate `../harnesses-private` being absent.
- Chops is a viewer of installed harness paths, not a source of truth.

## Proposed Layout

```text
harnesses/
  shared/
    skills/
    agents/
    rules/
    mcps/
  claude/
    skills/
    agents/
    rules/
    settings/
  codex/
    skills/
    agents/
    rules/
    settings/
  gemini/
  opencode/
```

## Discovery Before Symlinks

Before changing live paths, document where each harness actually discovers
assets:

- Global / Chops: `~/.agents/skills`
- Claude Code: `~/.claude/skills` and any global roots it also reads
- Codex: `~/.codex/skills`, built-in skills, and plugin-provided skills

Choose symlink routes only after discovery routes are clear. The goal is one
visible route for each shared asset, with harness-specific routes only for real
exceptions.

## Workspace Audits

Use the read-only harness guide audit to find repo-local instruction files that
may need cleanup:

```bash
scripts/audit-harness-guides.sh --dry-run
scripts/audit-harness-guides.sh --execute
scripts/audit-harness-guides.sh --execute --all --format tsv
```

The audit reports `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` size metrics plus
repo-local skill references. Large guide files are review signals, not failures.
