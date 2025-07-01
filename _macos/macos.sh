#!/usr/bin/env bash
set -euo pipefail

# Default values
MODE="show"
CONFIG_FILE=""
DRY_RUN=false
# shellcheck disable=SC2034  # VERBOSE is reserved for future use
VERBOSE=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

success() {
  echo -e "${GREEN}✓${NC} $*"
}

warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

error() {
  echo -e "${RED}✗${NC} $*" >&2
}

section() {
  echo
  echo -e "${GREEN}=== $* ===${NC}"
  echo
}

# Show system information
show_system_info() {
  section "System Information"

  info "macOS Version: $(sw_vers -productVersion)"
  info "Build: $(sw_vers -buildVersion)"
  info "Hardware: $(sysctl -n hw.model)"
  info "Architecture: $(uname -m)"

  # Check if Apple Silicon
  if [[ "$(uname -m)" == "arm64" ]]; then
    success "Running on Apple Silicon"
  else
    warning "Running on Intel (x86_64)"
  fi

  # Current user info
  info "Current User: $(whoami)"
  info "User ID: $(id -u)"
  info "Home Directory: $HOME"
}

# Show shell configuration
show_shell_info() {
  section "Shell Configuration"

  info "Current Shell: $SHELL"
  if [[ -f /etc/shells ]]; then
    info "Available Shells:"
    while IFS= read -r shell; do
      echo "  - $shell"
    done </etc/shells
  else
    warning "Cannot read /etc/shells"
  fi

  # Check for Homebrew bash
  if [[ -f "/opt/homebrew/bin/bash" ]]; then
    success "Homebrew bash found at /opt/homebrew/bin/bash"
  elif [[ -f "/usr/local/bin/bash" ]]; then
    success "Homebrew bash found at /usr/local/bin/bash"
  else
    warning "Homebrew bash not found"
  fi
}

# Show installed applications
show_applications() {
  section "Applications"

  if [[ -d /Applications ]]; then
    info "Applications in /Applications:"
    local app_count=0
    while IFS= read -r app; do
      if [[ -n "$app" ]]; then
        echo "  - $(basename "$app" .app)"
        ((app_count++))
      fi
    done < <(find /Applications -maxdepth 1 -name "*.app" 2>/dev/null | sort)
    info "Total: $app_count applications"
  else
    warning "Applications directory not found"
  fi

  # Check for specific apps we might need
  echo
  info "Checking for common applications:"
  local apps=("Google Chrome" "1Password 7" "Visual Studio Code" "iTerm")
  for app in "${apps[@]}"; do
    if [[ -d "/Applications/$app.app" ]]; then
      success "$app is installed"
    else
      warning "$app is not installed"
    fi
  done
}

# Show Homebrew status
show_homebrew_info() {
  section "Homebrew"

  if command -v brew >/dev/null 2>&1; then
    success "Homebrew is installed at $(which brew)"
    info "Homebrew version: $(brew --version | head -1)"

    # Check if this is the expected location for Apple Silicon
    if [[ "$(uname -m)" == "arm64" ]] && [[ "$(which brew)" != "/opt/homebrew/bin/brew" ]]; then
      warning "Homebrew is not in the standard Apple Silicon location (/opt/homebrew)"
    fi

    # Show some stats
    info "Installed formulae: $(brew list --formula | wc -l | tr -d ' ')"
    info "Installed casks: $(brew list --cask | wc -l | tr -d ' ')"
  else
    error "Homebrew is not installed"
    info "Install from: https://brew.sh"
  fi
}

# Show current defaults
show_current_defaults() {
  section "Current System Preferences"

  # Dock settings
  echo "Dock:"
  info "  Size: $(defaults read com.apple.dock tilesize 2>/dev/null || echo 'default')"
  info "  Position: $(defaults read com.apple.dock orientation 2>/dev/null || echo 'bottom')"
  info "  Auto-hide: $(defaults read com.apple.dock autohide 2>/dev/null || echo '0')"
  info "  Show recent apps: $(defaults read com.apple.dock show-recents 2>/dev/null || echo '1')"

  echo
  echo "Finder:"
  info "  Show hidden files: $(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo 'NO')"
  info "  Show file extensions: $(defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo '0')"
  info "  Default view style: $(defaults read com.apple.finder FXPreferredViewStyle 2>/dev/null || echo 'icnv')"

  echo
  echo "Keyboard:"
  info "  Key repeat rate: $(defaults read NSGlobalDomain KeyRepeat 2>/dev/null || echo 'default')"
  info "  Initial key repeat: $(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null || echo 'default')"

  echo
  echo "Trackpad:"
  info "  Tap to click: $(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking 2>/dev/null || echo '0')"
  info "  Natural scrolling: $(defaults read NSGlobalDomain com.apple.swipescrolldirection 2>/dev/null || echo '1')"
}

# Apply configuration from YAML
apply_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    error "Configuration file not found: $config_file"
    return 1
  fi

  # Check for yq
  if ! command -v yq >/dev/null 2>&1; then
    error "yq is required to parse YAML configuration files"
    info "Install with: brew install yq"
    return 1
  fi

  section "Applying Configuration: $config_file"

  # Apply each section
  apply_system_settings "$config_file"
  apply_dock_settings "$config_file"
  apply_finder_settings "$config_file"
  apply_keyboard_settings "$config_file"
  apply_trackpad_settings "$config_file"
  apply_mouse_settings "$config_file"
  apply_screenshot_settings "$config_file"
  apply_developer_settings "$config_file"
  apply_windows_settings "$config_file"
  apply_mission_control_settings "$config_file"
  apply_stage_manager_settings "$config_file"
  apply_widgets_settings "$config_file"
  apply_display_settings "$config_file"

  if [[ "$DRY_RUN" == "false" ]]; then
    info ""
    info "Restarting affected services..."
    
    # Restart Dock for dock-related changes
    killall Dock 2>/dev/null || true
    
    # Restart SystemUIServer for menu bar changes
    killall SystemUIServer 2>/dev/null || true
    
    # Restart Finder for Finder-related changes
    killall Finder 2>/dev/null || true
    
    # Activate settings using private framework (needed for scroll direction changes)
    if [[ -x "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings" ]]; then
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
    fi
    
    success "Configuration applied. Some changes may still require logout or restart."
  fi
}

# Apply system settings
apply_system_settings() {
  local config_file="$1"
  local section="system"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "System Settings:"

    # Appearance mode
    local appearance
    appearance=$(yq ".$section.appearance" "$config_file")
    if [[ "$appearance" != "null" ]]; then
      case "$appearance" in
        "Dark")
          apply_default "Appearance mode" "NSGlobalDomain" "AppleInterfaceStyle" "Dark"
          ;;
        "Light")
          # Light mode means removing the AppleInterfaceStyle key
          if [[ "$DRY_RUN" == "false" ]]; then
            defaults delete NSGlobalDomain AppleInterfaceStyle 2>/dev/null || true
            success "Appearance mode: changed to Light"
          else
            local current
            current=$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || echo "<not set>")
            if [[ "$current" != "<not set>" ]]; then
              warning "[DRY RUN] Would change Appearance mode from 'Dark' to 'Light'"
            else
              success "Appearance mode: already set to Light"
            fi
          fi
          ;;
        "Auto")
          apply_default "Appearance mode" "NSGlobalDomain" "AppleInterfaceStyleSwitchesAutomatically" "1"
          ;;
      esac
    fi

    # Show hidden files
    local show_hidden
    show_hidden=$(yq ".$section.show_hidden_files" "$config_file")
    if [[ "$show_hidden" != "null" ]]; then
      local value
      value=$([[ "$show_hidden" == "true" ]] && echo "YES" || echo "NO")
      apply_default "Show hidden files" "com.apple.finder" "AppleShowAllFiles" "$value"
    fi

    # Show all extensions
    local show_extensions
    local show_extensions
    show_extensions=$(yq ".$section.show_all_extensions" "$config_file")
    if [[ "$show_extensions" != "null" ]]; then
      local value
      value=$([[ "$show_extensions" == "true" ]] && echo "1" || echo "0")
      apply_default "Show all file extensions" "NSGlobalDomain" "AppleShowAllExtensions" "$value"
    fi
  fi
}

# Apply dock settings
apply_dock_settings() {
  local config_file="$1"
  local section="dock"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Dock Settings:"

    # Dock size
    local size
    size=$(yq ".$section.size" "$config_file")
    if [[ "$size" != "null" ]]; then
      apply_default "Dock size" "com.apple.dock" "tilesize" "$size"
    fi

    # Position
    local position
    position=$(yq ".$section.position" "$config_file")
    if [[ "$position" != "null" ]]; then
      apply_default "Dock position" "com.apple.dock" "orientation" "$position"
    fi

    # Auto-hide
    local auto_hide
    auto_hide=$(yq ".$section.auto_hide" "$config_file")
    if [[ "$auto_hide" != "null" ]]; then
      local value
      value=$([[ "$auto_hide" == "true" ]] && echo "1" || echo "0")
      apply_default "Auto-hide dock" "com.apple.dock" "autohide" "$value"
    fi

    # Show recents
    local show_recents
    show_recents=$(yq ".$section.show_recents" "$config_file")
    if [[ "$show_recents" != "null" ]]; then
      local value
      value=$([[ "$show_recents" == "true" ]] && echo "1" || echo "0")
      apply_default "Show recent apps" "com.apple.dock" "show-recents" "$value"
    fi

    # Minimize effect
    local minimize_effect
    minimize_effect=$(yq ".$section.minimize_effect" "$config_file")
    if [[ "$minimize_effect" != "null" ]]; then
      apply_default "Minimize effect" "com.apple.dock" "mineffect" "$minimize_effect"
    fi

    # Magnification
    local magnification
    magnification=$(yq ".$section.magnification" "$config_file")
    if [[ "$magnification" != "null" ]]; then
      local value
      value=$([[ "$magnification" == "true" ]] && echo "1" || echo "0")
      apply_default "Dock magnification" "com.apple.dock" "magnification" "$value"
    fi

    # Magnification size
    local mag_size
    mag_size=$(yq ".$section.magnification_size" "$config_file")
    if [[ "$mag_size" != "null" ]]; then
      apply_default "Dock magnification size" "com.apple.dock" "largesize" "$mag_size"
    fi

    # Animate opening applications
    local animate_opening
    animate_opening=$(yq ".$section.animate_opening" "$config_file")
    if [[ "$animate_opening" != "null" ]]; then
      local value
      value=$([[ "$animate_opening" == "true" ]] && echo "1" || echo "0")
      apply_default "Animate opening applications" "com.apple.dock" "launchanim" "$value"
    fi

    # Show indicators for open applications
    local show_indicators
    show_indicators=$(yq ".$section.show_indicators" "$config_file")
    if [[ "$show_indicators" != "null" ]]; then
      local value
      value=$([[ "$show_indicators" == "true" ]] && echo "1" || echo "0")
      apply_default "Show indicators for open apps" "com.apple.dock" "show-process-indicators" "$value"
    fi

    # Minimize to application icon
    local minimize_to_app
    minimize_to_app=$(yq ".$section.minimize_to_app" "$config_file")
    if [[ "$minimize_to_app" != "null" ]]; then
      local value
      value=$([[ "$minimize_to_app" == "true" ]] && echo "1" || echo "0")
      apply_default "Minimize to application icon" "com.apple.dock" "minimize-to-application" "$value"
    fi
    
    # Manage dock applications
    local manage_apps
    manage_apps=$(yq ".$section.manage_apps" "$config_file")
    if [[ "$manage_apps" == "true" ]]; then
      warning "Dock application management is enabled"
      
      # Get current dock apps to check for duplicates
      local current_dock_apps
      current_dock_apps=$(defaults read com.apple.dock persistent-apps 2>/dev/null | grep -o '"_CFURLString" = "[^"]*"' | sed 's/"_CFURLString" = "//; s/"$//; s|^file://||; s|/$||' | python3 -c "import sys, urllib.parse; [print(urllib.parse.unquote(line.strip())) for line in sys.stdin]" || echo "")
      
      # Check if we should clear dock first
      local clear_first
      clear_first=$(yq ".$section.clear_dock_first" "$config_file")
      if [[ "$clear_first" == "true" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
          info "Clearing dock..."
          defaults write com.apple.dock persistent-apps -array
          success "Dock cleared"
          current_dock_apps=""  # Reset since we cleared
        else
          warning "[DRY RUN] Would clear all dock applications"
        fi
      fi
      
      # Add specified apps
      local apps_count
      apps_count=$(yq ".$section.apps | length" "$config_file")
      if [[ "$apps_count" -gt 0 ]]; then
        info "Processing $apps_count applications for dock..."
        local added_count=0
        local skipped_count=0
        
        for ((i=0; i<apps_count; i++)); do
          local app_path
          app_path=$(yq ".$section.apps[$i]" "$config_file")
          if [[ -e "$app_path" ]]; then
            # Check if app is already in dock
            if echo "$current_dock_apps" | grep -qF "$app_path"; then
              info "Already in dock: $app_path"
              ((skipped_count++)) || true
            else
              if [[ "$DRY_RUN" == "false" ]]; then
                defaults write com.apple.dock persistent-apps -array-add \
                  "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app_path</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
                success "Added to dock: $app_path"
                ((added_count++)) || true
              else
                info "[DRY RUN] Would add to dock: $app_path"
              fi
            fi
          else
            warning "App not found: $app_path"
          fi
        done
        
        if [[ "$DRY_RUN" == "false" ]]; then
          info "Summary: Added $added_count apps, skipped $skipped_count already present"
        fi
      fi
    fi
  fi
}

# Apply finder settings
apply_finder_settings() {
  local config_file="$1"
  local section="finder"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Finder Settings:"

    # Default view
    local default_view
    default_view=$(yq ".$section.default_view" "$config_file")
    if [[ "$default_view" != "null" ]]; then
      apply_default "Default view style" "com.apple.finder" "FXPreferredViewStyle" "$default_view"
    fi

    # Show path bar
    local show_path_bar
    show_path_bar=$(yq ".$section.show_path_bar" "$config_file")
    if [[ "$show_path_bar" != "null" ]]; then
      local value
      value=$([[ "$show_path_bar" == "true" ]] && echo "1" || echo "0")
      apply_default "Show path bar" "com.apple.finder" "ShowPathbar" "$value"
    fi

    # Show status bar
    local show_status_bar
    show_status_bar=$(yq ".$section.show_status_bar" "$config_file")
    if [[ "$show_status_bar" != "null" ]]; then
      local value
      value=$([[ "$show_status_bar" == "true" ]] && echo "1" || echo "0")
      apply_default "Show status bar" "com.apple.finder" "ShowStatusBar" "$value"
    fi

    # Folders on top
    local folders_on_top
    folders_on_top=$(yq ".$section.folders_on_top" "$config_file")
    if [[ "$folders_on_top" != "null" ]]; then
      local value
      value=$([[ "$folders_on_top" == "true" ]] && echo "1" || echo "0")
      apply_default "Keep folders on top" "com.apple.finder" "_FXSortFoldersFirst" "$value"
    fi
  fi
}

# Apply keyboard settings
apply_keyboard_settings() {
  local config_file="$1"
  local section="keyboard"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Keyboard Settings:"

    # Key repeat
    local key_repeat
    key_repeat=$(yq ".$section.key_repeat" "$config_file")
    if [[ "$key_repeat" != "null" ]]; then
      apply_default "Key repeat rate" "NSGlobalDomain" "KeyRepeat" "$key_repeat"
    fi

    # Initial key repeat
    local initial_key_repeat
    initial_key_repeat=$(yq ".$section.initial_key_repeat" "$config_file")
    if [[ "$initial_key_repeat" != "null" ]]; then
      apply_default "Initial key repeat" "NSGlobalDomain" "InitialKeyRepeat" "$initial_key_repeat"
    fi
  fi
}

# Apply trackpad settings
apply_trackpad_settings() {
  local config_file="$1"
  local section="trackpad"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Trackpad Settings:"

    # Tap to click
    local tap_to_click
    tap_to_click=$(yq ".$section.tap_to_click" "$config_file")
    if [[ "$tap_to_click" != "null" ]]; then
      local value
      value=$([[ "$tap_to_click" == "true" ]] && echo "1" || echo "0")
      apply_default "Tap to click" "com.apple.driver.AppleBluetoothMultitouch.trackpad" "Clicking" "$value"
    fi

    # Natural scrolling
    local natural_scrolling
    natural_scrolling=$(yq ".$section.natural_scrolling" "$config_file")
    if [[ "$natural_scrolling" != "null" ]]; then
      local value
      value=$([[ "$natural_scrolling" == "true" ]] && echo "1" || echo "0")
      apply_default "Natural scrolling" "NSGlobalDomain" "com.apple.swipescrolldirection" "$value"
    fi

    # Tracking speed - note: this is a float value
    local tracking_speed
    tracking_speed=$(yq ".$section.tracking_speed" "$config_file")
    if [[ "$tracking_speed" != "null" ]]; then
      apply_default "Tracking speed" "NSGlobalDomain" "com.apple.trackpad.scaling" "$tracking_speed"
    fi
  fi
}

# Apply mouse settings
apply_mouse_settings() {
  local config_file="$1"
  local section="mouse"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Mouse Settings:"

    # Natural scrolling for mouse
    # NOTE: macOS links mouse and trackpad scroll direction - they cannot be set independently
    local natural_scrolling
    natural_scrolling=$(yq ".$section.natural_scrolling" "$config_file")
    if [[ "$natural_scrolling" != "null" ]]; then
      local value
      value=$([[ "$natural_scrolling" == "true" ]] && echo "1" || echo "0")
      
      # Set all possible mouse scroll settings to ensure consistency
      # Global scroll direction (primary setting)
      apply_default "Scroll direction (global)" "NSGlobalDomain" "com.apple.swipescrolldirection" "$value"
      
      # Apple Magic Mouse
      apply_default "Mouse natural scrolling (Magic Mouse)" "com.apple.AppleMultitouchMouse" "MouseVerticalScroll" "$value"
      
      # Bluetooth mice
      apply_default "Mouse natural scrolling (Bluetooth)" "com.apple.driver.AppleBluetoothMultitouch.mouse" "MouseVerticalScroll" "$value"
      
      # HID/Generic mice (same logic as others: 0=natural OFF, 1=natural ON)
      apply_default "Mouse natural scrolling (HID/Generic)" "com.apple.driver.AppleHIDMouse" "ScrollV" "$value"
      
    fi
  fi
}

# Apply screenshot settings
apply_screenshot_settings() {
  local config_file="$1"
  local section="screenshots"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Screenshot Settings:"

    # Location
    local location
    location=$(yq ".$section.location" "$config_file")
    if [[ "$location" != "null" ]]; then
      # Expand tilde in path
      location="${location/#\~/$HOME}"
      if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$location"
      fi
      apply_default "Screenshot location" "com.apple.screencapture" "location" "$location"
    fi

    # Format
    local format
    format=$(yq ".$section.format" "$config_file")
    if [[ "$format" != "null" ]]; then
      apply_default "Screenshot format" "com.apple.screencapture" "type" "$format"
    fi

    # Include date
    local include_date
    include_date=$(yq ".$section.include_date" "$config_file")
    if [[ "$include_date" != "null" ]]; then
      local value
      value=$([[ "$include_date" == "false" ]] && echo "1" || echo "0")
      apply_default "Include date in filename" "com.apple.screencapture" "include-date" "$value"
    fi

    # Show thumbnail
    local show_thumbnail
    show_thumbnail=$(yq ".$section.show_thumbnail" "$config_file")
    if [[ "$show_thumbnail" != "null" ]]; then
      local value
      value=$([[ "$show_thumbnail" == "true" ]] && echo "1" || echo "0")
      apply_default "Show thumbnail" "com.apple.screencapture" "show-thumbnail" "$value"
    fi
  fi
}

# Apply developer settings
apply_developer_settings() {
  local config_file="$1"
  local section="developer"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Developer Settings:"

    # Show path in title
    local show_path_in_title
    show_path_in_title=$(yq ".$section.show_path_in_title" "$config_file")
    if [[ "$show_path_in_title" != "null" ]]; then
      local value
      value=$([[ "$show_path_in_title" == "true" ]] && echo "1" || echo "0")
      apply_default "Show path in Finder title" "com.apple.finder" "_FXShowPosixPathInTitle" "$value"
    fi

    # Safari developer menu
    local safari_developer
    safari_developer=$(yq ".$section.safari_developer_menu" "$config_file")
    if [[ "$safari_developer" != "null" ]]; then
      local value
      value=$([[ "$safari_developer" == "true" ]] && echo "1" || echo "0")
      apply_default "Safari developer menu" "com.apple.Safari" "IncludeDevelopMenu" "$value"
      apply_default "Safari developer extras" "com.apple.Safari" "WebKitDeveloperExtrasEnabledPreferenceKey" "$value"
    fi
  fi
}

# Apply windows settings
apply_windows_settings() {
  local config_file="$1"
  local section="windows"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Windows Settings:"

    # Prefer tabs
    local prefer_tabs
    prefer_tabs=$(yq ".$section.prefer_tabs" "$config_file")
    if [[ "$prefer_tabs" != "null" ]]; then
      apply_default "Prefer tabs when opening documents" "NSGlobalDomain" "AppleWindowTabbingMode" "$prefer_tabs"
    fi

    # Ask to keep changes
    local ask_to_keep_changes
    ask_to_keep_changes=$(yq ".$section.ask_to_keep_changes" "$config_file")
    if [[ "$ask_to_keep_changes" != "null" ]]; then
      local value
      value=$([[ "$ask_to_keep_changes" == "false" ]] && echo "1" || echo "0")
      apply_default "Ask to keep changes when closing" "NSGlobalDomain" "NSCloseAlwaysConfirmsChanges" "$value"
    fi

    # Close windows when quitting
    local close_windows_on_quit
    close_windows_on_quit=$(yq ".$section.close_windows_on_quit" "$config_file")
    if [[ "$close_windows_on_quit" != "null" ]]; then
      local value
      value=$([[ "$close_windows_on_quit" == "false" ]] && echo "1" || echo "0")
      apply_default "Close windows when quitting app" "NSGlobalDomain" "NSQuitAlwaysKeepsWindows" "$value"
    fi

    # Double-click title bar action
    local double_click_action
    double_click_action=$(yq ".$section.double_click_title_bar" "$config_file")
    if [[ "$double_click_action" != "null" ]] && [[ "$double_click_action" != "finder.double_click_title_bar" ]]; then
      apply_default "Double-click title bar action" "NSGlobalDomain" "AppleActionOnDoubleClick" "$double_click_action"
    fi

    # Edge tiling
    local edge_tiling
    edge_tiling=$(yq ".$section.edge_tiling" "$config_file")
    if [[ "$edge_tiling" != "null" ]]; then
      local value
      value=$([[ "$edge_tiling" == "true" ]] && echo "1" || echo "0")
      apply_default "Drag windows to screen edges to tile" "com.apple.WindowManager" "EnableTiledWindowMargins" "$value"
    fi

    # Tiled margins
    local tiled_margins
    tiled_margins=$(yq ".$section.tiled_margins" "$config_file")
    if [[ "$tiled_margins" != "null" ]]; then
      local value
      value=$([[ "$tiled_margins" == "true" ]] && echo "1" || echo "0")
      apply_default "Tiled windows have margins" "com.apple.WindowManager" "EnableTiledWindowMargins" "$value"
    fi
  fi
}

# Apply mission control settings
apply_mission_control_settings() {
  local config_file="$1"
  local section="mission_control"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Mission Control Settings:"

    # Auto rearrange spaces
    local auto_rearrange
    auto_rearrange=$(yq ".$section.auto_rearrange_spaces" "$config_file")
    if [[ "$auto_rearrange" != "null" ]]; then
      local value
      value=$([[ "$auto_rearrange" == "true" ]] && echo "1" || echo "0")
      apply_default "Auto rearrange Spaces" "com.apple.dock" "mru-spaces" "$value"
    fi

    # Switch to space with windows
    local switch_to_space
    switch_to_space=$(yq ".$section.switch_to_space_with_windows" "$config_file")
    if [[ "$switch_to_space" != "null" ]]; then
      local value
      value=$([[ "$switch_to_space" == "true" ]] && echo "1" || echo "0")
      apply_default "Switch to Space with open windows" "NSGlobalDomain" "AppleSpacesSwitchOnActivate" "$value"
    fi

    # Group windows by app
    local group_by_app
    group_by_app=$(yq ".$section.group_by_app" "$config_file")
    if [[ "$group_by_app" != "null" ]]; then
      local value
      value=$([[ "$group_by_app" == "true" ]] && echo "1" || echo "0")
      apply_default "Group windows by application" "com.apple.dock" "expose-group-by-app" "$value"
    fi

    # Displays have separate spaces
    local separate_spaces
    separate_spaces=$(yq ".$section.displays_have_separate_spaces" "$config_file")
    if [[ "$separate_spaces" != "null" ]]; then
      local value
      value=$([[ "$separate_spaces" == "true" ]] && echo "1" || echo "0")
      apply_default "Displays have separate Spaces" "com.apple.spaces" "spans-displays" "$value"
    fi
  fi
}

# Apply stage manager settings
apply_stage_manager_settings() {
  local config_file="$1"
  local section="stage_manager"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Stage Manager Settings:"

    # Enable stage manager
    local enabled
    enabled=$(yq ".$section.enabled" "$config_file")
    if [[ "$enabled" != "null" ]]; then
      local value
      value=$([[ "$enabled" == "true" ]] && echo "1" || echo "0")
      apply_default "Stage Manager enabled" "com.apple.WindowManager" "GloballyEnabled" "$value"
    fi

    # Show recent apps
    local show_recent
    show_recent=$(yq ".$section.show_recent_apps" "$config_file")
    if [[ "$show_recent" != "null" ]]; then
      local value
      value=$([[ "$show_recent" == "true" ]] && echo "1" || echo "0")
      apply_default "Show recent apps in Stage Manager" "com.apple.WindowManager" "AutoHide" "$value"
    fi

    # Click wallpaper to reveal desktop
    local click_wallpaper
    click_wallpaper=$(yq ".$section.click_wallpaper_to_reveal" "$config_file")
    if [[ "$click_wallpaper" != "null" ]]; then
      case "$click_wallpaper" in
      "Always") apply_default "Click wallpaper to reveal desktop" "com.apple.WindowManager" "HideDesktop" "0" ;;
      "Only in Stage Manager") apply_default "Click wallpaper to reveal desktop" "com.apple.WindowManager" "HideDesktop" "1" ;;
      "Never") apply_default "Click wallpaper to reveal desktop" "com.apple.WindowManager" "HideDesktop" "2" ;;
      esac
    fi
  fi
}

# Apply widgets settings
apply_widgets_settings() {
  local config_file="$1"
  local section="widgets"

  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Widget Settings:"

    # Widget style
    local style
    style=$(yq ".$section.style" "$config_file")
    if [[ "$style" != "null" ]]; then
      case "$style" in
      "Automatic") apply_default "Widget style" "com.apple.widgets" "colorScheme" "0" ;;
      "Monochrome") apply_default "Widget style" "com.apple.widgets" "colorScheme" "1" ;;
      "Full Color") apply_default "Widget style" "com.apple.widgets" "colorScheme" "2" ;;
      esac
    fi
  fi
}

# Apply display settings
apply_display_settings() {
  local config_file="$1"
  local section="displays"
  
  if ! yq ".$section" "$config_file" | grep -q '^null$'; then
    echo "Display Settings:"
    
    
    # Check if we have any external displays
    local has_external=false
    local is_builtin_main=false
    
    # Check current main display
    if system_profiler SPDisplaysDataType 2>/dev/null | grep -B1 "Main Display: Yes" | grep -q "Built-in"; then
      is_builtin_main=true
    else
      has_external=true
    fi
    
    # Get dock position preference based on display type
    local dock_position_key
    if [[ "$has_external" == "true" ]] && [[ "$is_builtin_main" == "false" ]]; then
      dock_position_key="external"
    else
      dock_position_key="builtin"
    fi
    
    local preferred_dock_position
    preferred_dock_position=$(yq ".displays.dock_position.$dock_position_key" "$config_file" 2>/dev/null || echo "null")
    
    if [[ "$preferred_dock_position" != "null" ]]; then
      info "Display type: $dock_position_key, preferred dock position: $preferred_dock_position"
      
      # Apply the dock position
      local current_position
      current_position=$(defaults read com.apple.dock orientation 2>/dev/null || echo "")
      
      if [[ "$current_position" != "$preferred_dock_position" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
          defaults write com.apple.dock orientation "$preferred_dock_position"
          success "Dock position: changed to '$preferred_dock_position' for $dock_position_key display"
        else
          warning "[DRY RUN] Would change dock position from '$current_position' to '$preferred_dock_position' for $dock_position_key display"
        fi
      else
        success "Dock position: already set to '$preferred_dock_position' for $dock_position_key display"
      fi
    fi
    
  fi
}

# Apply a single default setting
apply_default() {
  local description="$1"
  local domain="$2"
  local key="$3"
  local value="$4"

  # Get current value
  local current_value
  current_value=$(defaults read "$domain" "$key" 2>/dev/null || echo "<not set>")

  # For comparison, treat empty strings consistently
  local compare_current="$current_value"
  local compare_new="$value"

  # If both are effectively empty, consider them equal
  if [[ -z "$compare_current" ]] && [[ -z "$compare_new" ]]; then
    success "$description: already set to default (empty)"
  elif [[ "$current_value" == "$value" ]]; then
    success "$description: already set to $value"
  else
    if [[ "$DRY_RUN" == "true" ]]; then
      # Display empty strings more clearly
      local display_current="$current_value"
      local display_new="$value"
      [[ -z "$display_current" ]] && display_current="<empty>"
      [[ -z "$display_new" ]] && display_new="<empty>"
      warning "[DRY RUN] Would change $description from '$display_current' to '$display_new'"
    else
      if defaults write "$domain" "$key" "$value"; then
        success "$description: changed from '$current_value' to '$value'"
      else
        error "Failed to set $description"
      fi
    fi
  fi
}

# Main execution
main() {
  case "$MODE" in
  show)
    show_system_info
    show_shell_info
    show_applications
    show_homebrew_info
    show_current_defaults
    ;;
  apply)
    if [[ -z "$CONFIG_FILE" ]]; then
      error "No configuration file specified"
      usage
      exit 1
    fi
    apply_config "$CONFIG_FILE"
    ;;
  *)
    error "Unknown mode: $MODE"
    exit 1
    ;;
  esac
}

usage() {
  echo "Usage: $0 [options] [config.yaml]"
  echo
  echo "Options:"
  echo "  -d, --dry-run     Show what would be changed without making changes"
  echo "  -v, --verbose     Show detailed output"
  echo "  -h, --help        Show this help message"
  echo
  echo "Examples:"
  echo "  $0                    # Show current system configuration"
  echo "  $0 personal.yaml      # Apply personal configuration"
  echo "  $0 -d work.yaml       # Dry run with work configuration"
  echo "  $0 ../personal.yaml   # Apply config from parent directory"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -d | --dry-run)
    DRY_RUN=true
    shift
    ;;
  -v | --verbose)
    # shellcheck disable=SC2034  # VERBOSE is reserved for future use
    VERBOSE=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *.yaml | *.yml)
    MODE="apply"
    CONFIG_FILE="$1"
    
    # If file doesn't exist as given, check in script's directory
    if [[ ! -f "$CONFIG_FILE" ]]; then
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      if [[ -f "$SCRIPT_DIR/$CONFIG_FILE" ]]; then
        CONFIG_FILE="$SCRIPT_DIR/$CONFIG_FILE"
      fi
    fi
    
    shift
    ;;
  *)
    error "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

main
