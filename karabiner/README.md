# Karabiner-Elements Configuration

Configuration for [Karabiner-Elements](https://karabiner-elements.pqrs.org/), a powerful keyboard customizer for macOS.

## Status

⚠️ **This configuration is kept for reference but NOT actively used on personal Mac.**

- **Personal Mac**: Uses [SuperKey](https://superkey.app/) instead (CapsLock → Hyper key)
- **Work Mac**: May use Karabiner-Elements if SuperKey cannot be installed
- **NOT in STOW_DIRS**: This config is intentionally excluded from auto-stowing
- **NOT in install configs**: Commented out in `_configs/host/common.yaml`

## Files

- `karabiner.json` - Main Karabiner-Elements configuration
- `assets/complex_modifications/` - Complex modification rules

## Key Mappings (If Karabiner Were Active)

### Hyper Key

**CapsLock** → **Hyper** (Shift+Command+Option+Control) or **Escape** (if pressed alone)

This provides a fifth modifier key for powerful shortcuts without conflicts.

### Hyper + Navigation

- **Hyper+H/J/K/L** → Arrow keys (Vim-style navigation)
- ~~**Hyper+N** → Right Arrow (accepts zsh autosuggestions)~~ **DEPRECATED** - Now used by Aerospace for layout switching
- **Hyper+Space** → Cmd+Space (Alfred/Spotlight)
- **Hyper+Semicolon** → Cmd+Right Arrow (end of line)

**Note**: Hyper+N was originally for zsh autosuggestions but is now used by Aerospace for `layout accordion`. With SuperKey, quick-press CapsLock accepts autosuggestions instead.

### Shift Keys

- **Left Shift** (alone) → Option+Left Arrow (word backward)
- **Right Shift** (alone) → Option+Right Arrow (word forward)
- **Both Shifts** together → Toggle Caps Lock

### Safety Features

- **Cmd+W** → Disabled (prevents accidental window close)
- **Cmd+Q** → Requires double-tap to quit apps
- **Cmd+Shift+Option+Ctrl+,/./** → Disabled (prevents accidental sysdiagnose)

### App Launcher (o + key)

Press **o** followed by another key to launch apps:

- **o+n** → Notion
- **o+m** → Mail
- **o+s** → Spotify
- **o+b** → Brave Browser
- **o+a** → Activity Monitor
- **o+c** → Visual Studio Code
- **o+i** → iTerm

### Other

- **Print Screen** → Opens Screenshot.app

## Installation (If Needed)

### Install Karabiner-Elements

```bash
brew install --cask karabiner-elements
```

### Stow Configuration

Since this is **not** in `STOW_DIRS`, you need to stow it manually:

```bash
# From dotfiles root
stow karabiner
```

Or copy files manually:

```bash
cp -r karabiner/.config/karabiner ~/.config/
```

## Current Alternative: SuperKey

On the personal Mac, [SuperKey](https://superkey.app/) is used instead because:

- ✅ Simpler setup
- ✅ Works on work Macs where Karabiner may have installation restrictions
- ✅ Native macOS integration
- ✅ "Quick press CapsLock to execute" feature for zsh autosuggestions

SuperKey provides the Hyper key functionality (CapsLock → Shift+Cmd+Option+Ctrl) which is all that's needed for:

- **Aerospace workspace switching** (Hyper+W/T/Y/U/I/O/P/[/])
- **Aerospace layout switching** (Hyper+N for accordion, Hyper+M for tiles)
- **zsh autosuggestion acceptance** (Quick-press CapsLock, not Hyper+N anymore)
- Other Hyper-based shortcuts

The move from Hyper+N (right arrow) to quick-press CapsLock for autosuggestions freed up Hyper+N/M for Aerospace layout control.

## Why Keep This Config?

This configuration is preserved for:

1. **Reference**: Documents the full keyboard customization setup
2. **Work Mac**: May need Karabiner if SuperKey can't be installed
3. **Backup**: Easy to restore if needed
4. **History**: Shows evolution of keyboard customization approach

## Related Configurations

- **Aerospace**: Uses Hyper key for workspace switching (`aerospace/.config/aerospace/aerospace.toml`)
- **zsh**: Hyper+N accepts autosuggestions (`zsh/.zshrc`)
- **SuperKey**: Current active keyboard customizer (not in dotfiles - GUI-configured app)
