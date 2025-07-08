# Nushell Configuration

A simple configuration for [Nushell](https://www.nushell.sh/) to get started.

## Features

- **Clean startup**: No welcome banner
- **Starship prompt**: Automatically set up if available
- **Basic aliases**: Common shortcuts (ll, la, git aliases)
- **Simple custom commands**: Example `greet` command
- **Navigation shortcuts**: `..` and `...` commands

## Structure

```
~/.config/nushell/
├── env.nu       # Minimal (following best practices)
└── config.nu    # Main configuration file
```

## Integration

### Ghostty
Configured as the default shell in Ghostty terminal.

### VSCode
Available as a terminal profile. To use:
- Open command palette (Cmd+Shift+P)
- Search for "Terminal: Select Default Profile"
- Choose "nu" for Nushell or keep "zsh" as default
- Create new terminal with specific profile: Terminal → New Terminal → Select "nu"

## Learning Nushell

The configuration includes:

1. **Basic settings**: Turn off banner, use SQLite history
2. **Simple aliases**: `ll`, `la`, and git shortcuts
3. **Custom command example**: `greet [name]` - try `greet` or `greet YourName`
4. **Navigation helpers**: `..` and `...` to go up directories

To explore more:
- Run `help` to see available commands
- Try `help commands` to see all commands
- Use `config nu` to edit your configuration

## Next Steps

Start simple and add more as you learn:
- Explore Nushell's structured data with `ls | where size > 1mb`
- Learn about pipelines with `sys | get cpu`
- Create your own commands with `def`

## Resources

- [Nushell Book](https://www.nushell.sh/book/)
- [Configuration Guide](https://www.nushell.sh/book/configuration.html)
- [Custom Commands](https://www.nushell.sh/book/custom_commands.html)