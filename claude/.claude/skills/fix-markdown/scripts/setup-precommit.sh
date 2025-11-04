#!/usr/bin/env bash
#
# Set up pre-commit configuration for markdown linting and emoji checking
#
# Usage: ./setup-precommit.sh [directory]
#
# Creates:
#   - .pre-commit-config.yaml (if not present)
#   - .git-hooks/check-emojis.sh (for pre-commit hook)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-.}"

cd "$TARGET_DIR"

echo "Pre-commit Setup for Markdown Linting"
echo "======================================"
echo ""

# Check if pre-commit is installed
if ! command -v pre-commit &> /dev/null; then
    echo "Warning: pre-commit is not installed"
    echo "Install with: brew install pre-commit"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if .pre-commit-config.yaml exists
if [[ -f .pre-commit-config.yaml ]]; then
    echo "Note: .pre-commit-config.yaml already exists"
    echo ""
    echo "To add markdown linting and emoji checking manually, add:"
    echo ""
    cat <<'EOF'
  # Markdown linting (without auto-fix)
  - repo: https://github.com/DavidAnson/markdownlint-cli2
    rev: v0.16.0
    hooks:
      - id: markdownlint-cli2

  # Check for emojis in markdown files
  - repo: local
    hooks:
      - id: check-emojis
        name: Check for emojis in markdown
        entry: .git-hooks/check-emojis.sh
        language: script
        files: \.(md|markdown)$
EOF
    echo ""
    exit 0
fi

# Offer to create .pre-commit-config.yaml
echo "No .pre-commit-config.yaml found"
echo ""
echo "This will create a minimal pre-commit config with:"
echo "  - markdownlint-cli2 (linting only, no auto-fix)"
echo "  - emoji checker (fails if emojis found)"
echo ""
read -p "Create .pre-commit-config.yaml? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Create .git-hooks directory and check-emojis.sh
mkdir -p .git-hooks

cat > .git-hooks/check-emojis.sh <<'EOF'
#!/usr/bin/env bash
# Check for emojis in markdown files
# This script is called by pre-commit for each staged markdown file

# Common emojis to check for
EMOJI_PATTERN="✅|❌|⚠️|🚀|💡|📝|🎯|🔥|⭐|🎉|👍|👎|✨|🛠️|📦|🔧|🏗️|📊|🌟"

# Check files passed as arguments
if grep -E "$EMOJI_PATTERN" "$@" > /dev/null 2>&1; then
    echo "Error: Emojis found in markdown files"
    grep -Hn -E "$EMOJI_PATTERN" "$@" | head -10
    echo ""
    echo "Run 'uv run scripts/detect-emojis.py --remove .' to fix automatically"
    exit 1
fi

exit 0
EOF

chmod +x .git-hooks/check-emojis.sh
echo "Created: .git-hooks/check-emojis.sh"

# Create .pre-commit-config.yaml
cat > .pre-commit-config.yaml <<'EOF'
# Pre-commit hooks for markdown quality
# Install: brew install pre-commit
# Setup: pre-commit install
# Run manually: pre-commit run --all-files

repos:
  # General file checks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
        name: Trim trailing whitespace
      - id: end-of-file-fixer
        name: Fix end of files
      - id: check-yaml
        name: Check yaml
      - id: check-merge-conflict
        name: Check for merge conflicts

  # Markdown linting (without auto-fix)
  - repo: https://github.com/DavidAnson/markdownlint-cli2
    rev: v0.16.0
    hooks:
      - id: markdownlint-cli2

  # Check for emojis in markdown files
  - repo: local
    hooks:
      - id: check-emojis
        name: Check for emojis in markdown
        entry: .git-hooks/check-emojis.sh
        language: script
        files: \.(md|markdown)$
EOF

echo "Created: .pre-commit-config.yaml"
echo ""
echo "Next steps:"
echo "  1. pre-commit install          # Install git hooks"
echo "  2. pre-commit run --all-files  # Test on all files"
echo ""
echo "To fix markdown issues before committing:"
echo "  - Run: ./scripts/fix-all-docs.sh ."
echo "  - Or use markdownlint-cli2 --fix"
