#!/bin/bash

set -euo pipefail

echo "=== Homebrew Git Credential Debugging ==="
echo

echo "1. Checking main Homebrew Git remotes..."
brew_repo=$(brew --repository)
cd "$brew_repo" || exit 1
git remote -v
echo

echo "2. Checking all tapped repositories and their remotes..."
find "$brew_repo/Library/Taps" -name ".git" -type d 2>/dev/null | while IFS= read -r tap_dir; do
  tap_path=$(dirname "$tap_dir")
  tap_name=$(echo "$tap_path" | sed "s|${brew_repo}/Library/Taps/||" | tr '/' '-')
  echo "Tap: $tap_name"
  if cd "$tap_path"; then
    git remote -v 2>/dev/null || echo "  (no remotes or not a git repo)"
  else
    echo "  (failed to access directory)"
  fi
  echo
done

echo "3. Checking Git credential configuration..."
cd "$brew_repo" || exit 1
git config --list | grep credential || echo "No credential configuration found"
echo

echo "4. Running brew update with verbose output..."
echo "   (This will show exactly what repositories Homebrew is trying to fetch)"
echo
brew_log=$(mktemp)
brew update --verbose 2>&1 | tee "$brew_log"
echo

echo "5. Analyzing output for authentication issues..."
if grep -q "could not read Username\|Authentication failed\|does not exist" "$brew_log"; then
  echo "⚠️  Found authentication/access issues:"
  grep -n "could not read Username\|Authentication failed\|does not exist\|failed to get" "$brew_log"
  echo
  echo "Problematic taps that may need to be removed:"
  grep "does not exist" "$brew_log" | sed 's/.*Error: \(.*\) does not exist.*/\1/' | while IFS= read -r tap; do
    echo "  brew untap $tap"
  done
else
  echo "✅ No authentication issues detected"
fi

rm -f "$brew_log"
echo
echo "=== Debug complete ==="