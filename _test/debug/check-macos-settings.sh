#!/bin/bash

echo "=== System Settings ==="
echo "Appearance: $(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || echo 'Light')"
echo "Show hidden files: $(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo 'FALSE')"
echo "Show all extensions: $(defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo '0')"
echo ""

echo "=== Dock Settings ==="
echo "Position: $(defaults read com.apple.dock orientation 2>/dev/null || echo 'bottom')"
echo "Auto-hide: $(defaults read com.apple.dock autohide 2>/dev/null || echo '0')"
echo "Show recents: $(defaults read com.apple.dock show-recents 2>/dev/null || echo '1')"
echo "Minimize effect: $(defaults read com.apple.dock mineffect 2>/dev/null || echo 'genie')"
echo "Animate opening: $(defaults read com.apple.dock launchanim 2>/dev/null || echo '1')"
echo "Show indicators: $(defaults read com.apple.dock show-process-indicators 2>/dev/null || echo '1')"
echo "Minimize to app: $(defaults read com.apple.dock minimize-to-application 2>/dev/null || echo '0')"
echo ""

echo "=== Finder Settings ==="
echo "Show path bar: $(defaults read com.apple.finder ShowPathbar 2>/dev/null || echo '0')"
echo "Show status bar: $(defaults read com.apple.finder ShowStatusBar 2>/dev/null || echo '0')"
echo ""

echo "=== Keyboard Settings ==="
echo "Key repeat: $(defaults read NSGlobalDomain KeyRepeat 2>/dev/null || echo '6')"
echo "Initial key repeat: $(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null || echo '25')"
echo ""

echo "=== Trackpad Settings ==="
echo "Tap to click: $(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking 2>/dev/null || echo '0')"
echo "Natural scrolling: $(defaults read NSGlobalDomain com.apple.swipescrolldirection 2>/dev/null || echo '1')"
echo ""

echo "=== Mission Control ==="
echo "Auto rearrange spaces: $(defaults read com.apple.dock mru-spaces 2>/dev/null || echo '1')"
echo "Group by app: $(defaults read com.apple.dock expose-group-by-app 2>/dev/null || echo '0')"
echo "Displays have separate spaces: $(defaults read com.apple.spaces spans-displays 2>/dev/null || echo '1')"