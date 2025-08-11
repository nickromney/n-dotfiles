# Ghostty Configuration

Modern configuration for [Ghostty](https://ghostty.org/), a fast, GPU-accelerated terminal emulator.

## Features

- **Advanced Font Support**:
  - Multiple font fallback chain (Monaco → JetBrainsMono Nerd Font)
  - Per-codepoint font mapping capability
  - Variable font support
  - Synthetic style generation
- **Background**: Fully opaque (1.0)
- **Scrollback**: 10,000 lines
- **macOS Integration**: Option as Alt
- **Shell Integration**: Automatic detection
- **Copy-on-select**: Direct to clipboard

## Installation

The configuration will be symlinked to `~/.config/ghostty/config` when you run:

```bash
make personal stow
```

or

```bash
./install.sh -s
```

## Customisation

### Fonts

Ghostty's font support is exceptional. You can:

1. **List available fonts**: `ghostty +list-fonts`
2. **Set multiple fallbacks** (each on its own line):

   ```toml
   font-family = Monaco
   font-family = "JetBrainsMono Nerd Font"
   font-family = "Apple Color Emoji"
   ```

3. **Map specific Unicode ranges** to fonts:

   ```toml
   font-codepoint-map = U+E000-U+F8FF="JetBrainsMono Nerd Font"
   ```

4. **Configure variable fonts**:

   ```toml
   font-variation = wght=450
   font-variation = slnt=-10
   ```

### Themes

Ghostty supports custom themes. Place theme files in `~/.config/ghostty/themes/` and reference them:

```toml
theme = catppuccin-mocha
```

### Quick Terminal

Uncomment the quick terminal settings to enable dropdown terminal:

```toml
quick-terminal-position = top
quick-terminal-screen = current
quick-terminal-animation-duration = 0.2
```

Then bind a global hotkey to toggle it.

## Resources

- [Ghostty Documentation](https://ghostty.org/docs)
- [Ghostty Themes](https://github.com/ghostty-org/ghostty-themes)
