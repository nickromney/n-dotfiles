#!/bin/bash

# Get the repository root (two levels up from _test/debug)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Check for required dependency: yq
if ! command -v yq >/dev/null 2>&1; then
    echo "Error: 'yq' is not installed. Please install yq to continue." >&2
    exit 1
fi

# Check for required YAML file
YAML_FILE="${REPO_ROOT}/_macos/work.yaml"
# Get the repository root (two levels up from _test/debug)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [ ! -f "$YAML_FILE" ]; then
    echo "Error: YAML file '$YAML_FILE' not found." >&2
    exit 1
fi
echo "=== Checking _macos/work.yaml against actual system settings ==="
echo ""

# Compare function
check_setting() {
    local name="$1"
    local yaml_value="$2"
    local actual_value="$3"

    if [[ "$yaml_value" == "$actual_value" ]]; then
        echo "✓ $name: $yaml_value (matches)"
    else
        echo "✗ $name: YAML=$yaml_value, ACTUAL=$actual_value (mismatch)"
    fi
}

# Get actual system values
appearance=$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || echo "Light")
hidden_files=$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo "FALSE")
show_extensions=$(defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo "0")
dock_position=$(defaults read com.apple.dock orientation 2>/dev/null || echo "bottom")
dock_autohide=$(defaults read com.apple.dock autohide 2>/dev/null || echo "0")
show_recents=$(defaults read com.apple.dock show-recents 2>/dev/null || echo "1")
animate_opening=$(defaults read com.apple.dock launchanim 2>/dev/null || echo "1")
show_indicators=$(defaults read com.apple.dock "show-process-indicators" 2>/dev/null || echo "1")
minimize_to_app=$(defaults read com.apple.dock minimize-to-application 2>/dev/null || echo "0")
path_bar=$(defaults read com.apple.finder ShowPathbar 2>/dev/null || echo "0")
status_bar=$(defaults read com.apple.finder ShowStatusBar 2>/dev/null || echo "0")
key_repeat=$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null || echo "6")
initial_repeat=$(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null || echo "25")
tap_to_click=$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking 2>/dev/null || echo "0")
natural_scroll=$(defaults read NSGlobalDomain com.apple.swipescrolldirection 2>/dev/null || echo "1")
auto_rearrange=$(defaults read com.apple.dock mru-spaces 2>/dev/null || echo "1")
group_by_app=$(defaults read com.apple.dock expose-group-by-app 2>/dev/null || echo "0")
separate_spaces=$(defaults read com.apple.spaces spans-displays 2>/dev/null || echo "1")

# Convert system values to YAML format
[[ "$hidden_files" == "YES" || "$hidden_files" == "TRUE" || "$hidden_files" == "1" ]] && hidden_files="true" || hidden_files="false"
[[ "$show_extensions" == "1" ]] && show_extensions="true" || show_extensions="false"
[[ "$dock_autohide" == "1" ]] && dock_autohide="true" || dock_autohide="false"
[[ "$show_recents" == "0" ]] && show_recents="false" || show_recents="true"
[[ "$animate_opening" == "0" ]] && animate_opening="false" || animate_opening="true"
[[ "$show_indicators" == "1" ]] && show_indicators="true" || show_indicators="false"
[[ "$minimize_to_app" == "1" ]] && minimize_to_app="true" || minimize_to_app="false"
[[ "$path_bar" == "1" ]] && path_bar="true" || path_bar="false"
[[ "$status_bar" == "1" ]] && status_bar="true" || status_bar="false"
[[ "$tap_to_click" == "1" ]] && tap_to_click="true" || tap_to_click="false"
[[ "$natural_scroll" == "0" ]] && natural_scroll="false" || natural_scroll="true"
[[ "$auto_rearrange" == "0" ]] && auto_rearrange="false" || auto_rearrange="true"
[[ "$group_by_app" == "1" ]] && group_by_app="true" || group_by_app="false"
[[ "$separate_spaces" == "1" ]] && separate_spaces="true" || separate_spaces="false"

# System
echo "=== System ==="
check_setting "Appearance" "$(yq '.system.appearance' "$REPO_ROOT/_macos/work.yaml")" "$appearance"
check_setting "Show hidden files" "$(yq '.system.show_hidden_files' "$REPO_ROOT/_macos/work.yaml")" "$hidden_files"
check_setting "Show all extensions" "$(yq '.system.show_all_extensions' "$REPO_ROOT/_macos/work.yaml")" "$show_extensions"

# Dock
echo ""
echo "=== Dock ==="
check_setting "Position" "$(yq '.dock.position' "$REPO_ROOT/_macos/work.yaml")" "$dock_position"
check_setting "Auto-hide" "$(yq '.dock.auto_hide' "$REPO_ROOT/_macos/work.yaml")" "$dock_autohide"
check_setting "Show recents" "$(yq '.dock.show_recents' "$REPO_ROOT/_macos/work.yaml")" "$show_recents"
check_setting "Animate opening" "$(yq '.dock.animate_opening' "$REPO_ROOT/_macos/work.yaml")" "$animate_opening"
check_setting "Show indicators" "$(yq '.dock.show_indicators' "$REPO_ROOT/_macos/work.yaml")" "$show_indicators"
check_setting "Minimize to app" "$(yq '.dock.minimize_to_app' "$REPO_ROOT/_macos/work.yaml")" "$minimize_to_app"

# Finder
echo ""
echo "=== Finder ==="
check_setting "Show path bar" "$(yq '.finder.show_path_bar' "$REPO_ROOT/_macos/work.yaml")" "$path_bar"
check_setting "Show status bar" "$(yq '.finder.show_status_bar' "$REPO_ROOT/_macos/work.yaml")" "$status_bar"

# Keyboard
echo ""
echo "=== Keyboard ==="
check_setting "Key repeat" "$(yq '.keyboard.key_repeat' "$REPO_ROOT/_macos/work.yaml")" "$key_repeat"
check_setting "Initial key repeat" "$(yq '.keyboard.initial_key_repeat' "$REPO_ROOT/_macos/work.yaml")" "$initial_repeat"

# Trackpad
echo ""
echo "=== Trackpad ==="
check_setting "Tap to click" "$(yq '.trackpad.tap_to_click' "$REPO_ROOT/_macos/work.yaml")" "$tap_to_click"
check_setting "Natural scrolling" "$(yq '.trackpad.natural_scrolling' "$REPO_ROOT/_macos/work.yaml")" "$natural_scroll"

# Mouse
echo ""
echo "=== Mouse ==="
# Get mouse natural scrolling setting
mouse_natural_scroll="$(defaults read -g com.apple.swipescrolldirection_mouse 2>/dev/null || echo "N/A")"
echo ""
echo "=== Mouse ==="
check_setting "Natural scrolling" "$(yq '.mouse.natural_scrolling' "$REPO_ROOT/_macos/work.yaml")" "$mouse_natural_scroll"

# Mission Control
echo ""
echo "=== Mission Control ==="
check_setting "Auto rearrange" "$(yq '.mission_control.auto_rearrange_spaces' "$REPO_ROOT/_macos/work.yaml")" "$auto_rearrange"
check_setting "Group by app" "$(yq '.mission_control.group_by_app' "$REPO_ROOT/_macos/work.yaml")" "$group_by_app"
check_setting "Separate spaces" "$(yq '.mission_control.displays_have_separate_spaces' "$REPO_ROOT/_macos/work.yaml")" "$separate_spaces"
