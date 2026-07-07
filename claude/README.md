# Claude Code Configuration

Configuration for [Claude Code](https://claude.com/claude-code), Anthropic's official CLI.

## Files

- `settings.json` - Claude Code settings including status line configuration
- `skills/` - Claude Code skill view, used as the target for `~/.claude/skills`
- `rules/` - Claude Code rules view, used as the target for `~/.claude/rules`

## Installation

```bash
# Using stow from repository root
stow claude

# Or using the stow entrypoint
./stow.sh claude
```

## Settings

### Status Line

The status line displays:

- **Current directory** (with `~` for home)
- **Git branch** (if in a git repository)
- **Git status indicators**:
  - ✓ = staged files
  - ! = modified files
  - ? = untracked files
- **Node version** (if package.json exists)
- **Terraform indicator** (if .tf files exist)
- **Current time** [HH:MM]

Example: `~/Developer/project git main ✓2 !1 ?3 󰎙 20.0.0 [14:23]`

### Settings

- `alwaysThinkingEnabled: false` - Disables automatic thinking mode

## Location

When stowed, this creates:

- `~/.claude/skills` → `claude/.claude/skills`
- `~/.claude/rules` → `claude/.claude/rules`

`~/.claude/settings.json` is currently ignored by this Stow package because
the live Claude directory also contains runtime state.
