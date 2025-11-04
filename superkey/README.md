# SuperKey Configuration

Configuration documentation for [SuperKey](https://superkey.app/), a keyboard customizer for macOS that provides Hyper key functionality.

## Status

✅ **Currently Active** - This is the primary keyboard customizer on personal Mac.

- **Personal Mac**: SuperKey is actively used
- **Work Mac**: May fall back to Karabiner-Elements if SuperKey can't be installed
- **No CLI**: SuperKey is GUI-configured, so no config files to version control
- **Documentation Only**: This directory exists to document the setup

## Why SuperKey?

SuperKey was chosen over Karabiner-Elements because:

- ✅ Simpler setup and configuration
- ✅ Works on work Macs where Karabiner may have installation restrictions
- ✅ Native macOS integration
- ✅ "Quick press CapsLock to execute" feature
- ✅ Lighter weight than Karabiner-Elements

## Installation

### Install SuperKey

```bash
# Download from website
open https://superkey.app/

# Or via Homebrew
brew install --cask superkey
```

### Launch and Configure

1. Open SuperKey from Applications
2. Grant Accessibility permissions in System Settings
3. Configure settings (see below)

## SuperKey Configuration

Since SuperKey is GUI-configured, here's the documented setup:

### Primary Feature: Hyper Key

**CapsLock** → **Hyper** (Shift+Command+Option+Control)

This converts CapsLock into a fifth modifier key, providing access to powerful shortcuts without conflicts.

### Quick Press Feature

**Quick press CapsLock** → Accepts zsh autosuggestions

This is configured in SuperKey settings and replaces the old Hyper+N mapping for autosuggestions.

## Current Hyper Key Usage

With SuperKey providing the Hyper key, these shortcuts are active:

### Aerospace Window Management

**Workspace Switching:**

- **Hyper+W** → Work workspace (browser profiles)
- **Hyper+T** → Terminal workspace (Ghostty, Kitty)
- **Hyper+Y** → YDE workspace (VSCode, Cursor, IDEs)
- **Hyper+U** → Utilities workspace (Finder, Preview, etc.)
- **Hyper+I** → Internet workspace (browsers)
- **Hyper+O** → Office workspace (Excel, Word, PowerPoint)
- **Hyper+P** → Productivity workspace (Obsidian, Things, Spotify, Claude)
- **Hyper+[** → Email workspace (HEY, Outlook)
- **Hyper+]** → Messaging workspace (Teams, WhatsApp, Slack, Zoom)

**Layout Control:**

- **Hyper+N** → Accordion layout (horizontal/vertical)
- **Hyper+M** → Tiles layout (horizontal/vertical)
- **Hyper+Semicolon** → Enter move mode (press Escape or Enter to exit)
  - **h** → Move window left
  - **j** → Move window down
  - **k** → Move window up
  - **l** → Move window right
  - **e** → Accordion layout (horizontal/vertical)
  - **f** → Fullscreen
  - **t** → Toggle floating/tiling layout (exits move mode)
  - **b** → Balance window sizes
  - **Escape/Enter** → Return to normal mode

**Window Focus:**

- **Alt+H** → Focus left
- **Alt+J** → Focus down
- **Alt+K** → Focus up
- **Alt+L** → Focus right

**Move Window + Switch Workspace:**

- **Hyper+2** → Move to Work workspace (W) and switch to it
- **Hyper+5** → Move to Terminal workspace (T) and switch to it
- **Hyper+6** → Move to YDE workspace (Y) and switch to it
- **Hyper+7** → Move to Utilities workspace (U) and switch to it
- **Hyper+8** → Move to Internet workspace (I) and switch to it
- **Hyper+9** → Move to Office workspace (O) and switch to it
- **Hyper+0** → Move to Productivity workspace (P) and switch to it
- **Hyper+Minus** → Move to Email workspace ([) and switch to it
- **Hyper+Equal** → Move to Messaging workspace (]) and switch to it

**Workspace Navigation:**

- **Hyper+H** → Workspace back-and-forth (toggle between last two workspaces)
- **Hyper+L** → Move workspace to next monitor

**Window Resizing:**

- **Alt+Shift+Minus** → Resize smart -100
- **Alt+Shift+Equal** → Resize smart +100

### zsh Autosuggestions

**Quick press CapsLock** → Accept current autosuggestion

This replaced the old Hyper+N mapping, freeing up Hyper+N for Aerospace layout control.

### Ghostty Terminal

**Shift+Enter** → Soft return (newline without submitting)

Configured in Ghostty config, works with SuperKey's Shift modifier.

## Workflow Evolution

The keyboard customization setup has evolved:

### Phase 1: Karabiner-Elements

- Used Karabiner for all keyboard customization
- Hyper+N → Right Arrow → Accept zsh suggestions
- Complex JSON configuration

### Phase 2: SuperKey (Current)

- Switched to SuperKey for simplicity
- Quick-press CapsLock → Accept zsh suggestions
- Freed up Hyper+N/M for Aerospace layouts
- GUI configuration instead of JSON

## Why No Config Files?

SuperKey stores its configuration in a proprietary format managed through the GUI. Unlike Karabiner-Elements which uses `karabiner.json`, SuperKey doesn't have a CLI or documented config file format.

This README serves as the "config" by documenting:

1. What SuperKey features are enabled
2. How the Hyper key is configured
3. What shortcuts depend on SuperKey
4. Installation and setup process

## Related Configurations

- **Aerospace**: Uses Hyper key for workspace/layout switching (`aerospace/.config/aerospace/aerospace.toml`)
- **Ghostty**: Uses Shift+Enter for soft returns (`ghostty/.config/ghostty/config`)
- **zsh**: Quick-press CapsLock accepts autosuggestions (via SuperKey)
- **Karabiner**: Legacy config kept for reference and work Mac fallback (`karabiner/`)

## Backup Strategy

Since SuperKey config isn't in version control:

1. **Document shortcuts** in this README (done!)
2. **Screenshot SuperKey settings** for reference
3. **Keep Karabiner config** as fallback for work Mac
4. **Test setup** after macOS updates

## Migration Back to Karabiner (If Needed)

If you need to switch back to Karabiner-Elements:

1. Quit SuperKey
2. Install Karabiner-Elements: `brew install --cask karabiner-elements`
3. Stow Karabiner config: `cd ~/Developer/personal/n-dotfiles && stow karabiner`
4. Update Karabiner config to match current shortcuts (Hyper+N/M for Aerospace)
5. Remove or update the Hyper+N → Right Arrow mapping

## Troubleshooting

### SuperKey Not Working

1. Check System Settings → Privacy & Security → Accessibility
2. Ensure SuperKey has permission
3. Restart SuperKey from Applications
4. Reboot if needed

### Conflicts with Karabiner

If both are running:

1. Quit Karabiner: `/Applications/Karabiner-Elements.app/Contents/Library/bin/karabiner_cli --quit-karabiner-elements`
2. Ensure only SuperKey is in Login Items

### Aerospace Shortcuts Not Working

1. Verify SuperKey is running and has Accessibility permissions
2. Test Hyper key: Press CapsLock+W (should not type 'W')
3. Check Aerospace is running: `aerospace list-workspaces`
4. Reload Aerospace config: `aerospace reload-config`

## Version

- **SuperKey**: GUI-based, check app for version
- **Last Updated**: 2025-10-10
- **macOS**: Tested on macOS Tahoe 26 (Darwin 25.0.0)
