# macOS Setup

Light-touch macOS configuration management that respects existing system settings and corporate device management.

## Usage

### Show Current Settings

```bash
# Display current system configuration
./macos.sh
```

### Apply Configuration

```bash
# Apply personal settings
./macos.sh personal.yaml

# Apply work settings (example)
./macos.sh work-example.yaml

# Dry run (show what would change)
./macos.sh -d personal.yaml
```

## Configuration Files

The `_macos/` directory contains:
- `macos.sh` - The main configuration script
- `personal.yaml` - Personal settings that match the current system state (December 2024)
- `work-example.yaml` - Conservative example for work machines
- `README.md` - This documentation

Configuration files are YAML-based and define system preferences to apply.

### Key Mapping

The YAML files use human-friendly key names that are automatically mapped to the actual macOS defaults keys:

| YAML Key | macOS Default Key | Domain |
|----------|-------------------|--------|
| `size` | `tilesize` | com.apple.dock |
| `position` | `orientation` | com.apple.dock |
| `auto_hide` | `autohide` | com.apple.dock |
| `show_recents` | `show-recents` | com.apple.dock |
| `minimize_effect` | `mineffect` | com.apple.dock |
| `prefer_tabs` | `AppleWindowTabbingMode` | NSGlobalDomain |

### Special Values

- **Empty strings (`""`)**: Represent system default values
- **Booleans**: Automatically converted to 0/1 for macOS
- **Case sensitivity**: Some values like `always` vs `Always` matter

### Available Settings

#### System
- `appearance`: System appearance mode ("Light", "Dark", or "Auto")
- `show_hidden_files`: Show hidden files in Finder
- `show_all_extensions`: Always show file extensions

#### Dock
- `tilesize`: Icon size (16-128, or empty string for default)
- `orientation`: Dock position (left, bottom, right, or empty string for default)
- `autohide`: Auto-hide the dock (0 or 1)
- `show-recents`: Show recent applications (0 or 1)
- `mineffect`: Animation effect (genie, scale, or empty string for default)
- `magnification`: Enable dock magnification on hover (0 or 1)
- `largesize`: Size when magnified (16-128)
- `launchanim`: Animate opening applications (0 or 1)
- `show-process-indicators`: Show indicators for open applications (0 or 1)
- `minimize-to-application`: Minimize windows into application icon (0 or 1)
- `manage_apps`: Enable dock application management (false by default)
- `clear_dock_first`: Clear all dock items before adding apps (requires manage_apps: true)
- `apps`: List of application paths to add to dock

Note: Empty strings (`""`) are valid values that represent system defaults

#### Finder
- `default_view`: Default view style (icnv, Nlsv, clmv, Flwv)
- `show_path_bar`: Show path bar at bottom
- `show_status_bar`: Show status bar
- `folders_on_top`: Keep folders on top when sorting
- `double_click_title_bar`: Action on double-click (Minimize, Zoom, None)

#### Windows
- `AppleWindowTabbingMode`: When to use tabs (always, fullscreen, manual) - in NSGlobalDomain
- `NSCloseAlwaysConfirmsChanges`: Ask to save changes when closing (0 = ask, 1 = don't ask) - in NSGlobalDomain
- `NSQuitAlwaysKeepsWindows`: Keep windows when quitting (0 = close, 1 = keep) - in NSGlobalDomain
- `AppleActionOnDoubleClick`: Double-click title bar action (Minimize, Maximize, None) - in NSGlobalDomain

Note: Window tiling features (edge tiling, margins) may not have corresponding defaults entries

#### Mission Control
- `mru-spaces`: Automatically rearrange Spaces based on most recent use (0 or 1)
- `AppleSpacesSwitchOnActivate`: Switch to Space with app windows (0 or 1) - in NSGlobalDomain
- `expose-group-by-app`: Group windows by application (0 or 1)
- `spans-displays`: Displays have separate Spaces (0 or 1) - in com.apple.spaces domain

Note: Some Mission Control settings may require different domains (NSGlobalDomain, com.apple.spaces)

#### Stage Manager (com.apple.WindowManager domain)
- `GloballyEnabled`: Enable Stage Manager (0 or 1)
- `AutoHide`: Auto-hide recent apps strip (0 or 1)
- `HideDesktop`: Click wallpaper behavior (0 = Always reveal, 1 = Only in Stage Manager, 2 = Never)

Note: Many Stage Manager UI settings may not have corresponding defaults entries

#### Widgets
- `show_on_desktop`: Show widgets on desktop
- `show_in_stage_manager`: Show widgets in Stage Manager
- `style`: Widget appearance (Automatic, Monochrome, Full Color)
- `use_iphone_widgets`: Use iPhone widgets

#### Keyboard
- `key_repeat`: Key repeat rate (0-120, lower is faster)
- `initial_key_repeat`: Delay before repeat (15-120)

#### Trackpad
- `tap_to_click`: Enable tap to click
- `natural_scrolling`: Scrolling direction
- `tracking_speed`: Pointer tracking speed (0-3)

#### Mouse
- `natural_scrolling`: Scrolling direction for mouse (separate from trackpad)

#### Displays
- `main_display_priority`: List of display names in preference order
  - First connected display in list becomes main
  - All other connected displays become extended
- `dock_position`: Dock position per display type
  - `external`: Position when external display is main
  - `builtin`: Position when built-in display is main

Note: macOS display arrangement requires manual configuration in System Settings.

#### Screenshots
- `location`: Where to save screenshots
- `format`: File format (png, jpg)
- `include_date`: Include timestamp in filename
- `show_thumbnail`: Show thumbnail after capture

#### Developer
- `show_path_in_title`: Show full path in Finder title
- `safari_developer_menu`: Enable Safari developer menu
- `show_all_extensions`: Force showing all file extensions

## Design Philosophy

1. **Light Touch**: Only change settings explicitly defined in configuration
2. **Corporate Friendly**: Respect device management and security policies
3. **Idempotent**: Running multiple times produces the same result
4. **Transparent**: Always show what will be changed before applying
5. **No Secrets**: Never store sensitive information in configurations

## Testing

The script includes comprehensive BATS tests:

```bash
cd _test
bats macos.bats
```

## Current System State

Many macOS defaults use empty strings (`""`) to represent default values. The `personal.yaml` file reflects the actual current state of the system, including these empty strings where appropriate.

## Notes

- Requires `yq` for YAML parsing (install with `brew install yq`)
- Some settings may require logout/restart to take effect
- Corporate-managed devices may override some settings
- Always test configurations in dry-run mode first
- Use `defaults read <domain> <key>` to check current values
- Empty strings in defaults often represent "use system default"