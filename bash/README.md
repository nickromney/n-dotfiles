# Bash Configuration

Minimal bash configuration for fallback environments where zsh or nushell aren't available.

## Design Philosophy

This is intentionally minimal. For full-featured shell experience, use:

- **zsh** - Primary shell (macOS default) with full tooling
- **nushell** - Modern shell with structured data

Bash config covers essentials for:

- CI/CD pipelines
- Docker containers
- Remote servers
- Emergency fallback

## Features Included

| Feature | Status | Notes |
|---------|--------|-------|
| History | ✓ | 100k entries, dedup, append mode |
| Homebrew | ✓ | macOS Intel and Apple Silicon |
| Starship | ✓ | Prompt (if installed) |
| FNM | ✓ | Node version manager |
| kubectl | ✓ | Completions and aliases |
| 1Password SSH | ✓ | macOS and Linux |
| PATH management | ✓ | Deduplication |
| Local overrides | ✓ | ~/.bashrc.local |

## Features NOT Included

These are available in zsh but intentionally omitted here:

- FZF integration and keybindings
- Zoxide (smart cd)
- EZA aliases
- Git aliases (lazygit, etc.)
- ZScaler certificate handling
- Podman socket setup
- Init script caching

## Local Customisation

Create `~/.bashrc.local` for machine-specific settings:

```bash
# Example ~/.bashrc.local
export MY_VAR="value"
alias custom="my-command"
```

This file is sourced last and can override any defaults.
