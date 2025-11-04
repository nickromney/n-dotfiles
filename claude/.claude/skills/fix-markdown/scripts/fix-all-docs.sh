#!/usr/bin/env bash
#
# Fix all auto-fixable markdown issues in documentation
#
# Usage: ./fix-all-docs.sh [directory]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-documentation}"

echo "Fixing markdown issues in: $TARGET_DIR"
echo ""

echo "Step 1: Running markdownlint auto-fix..."
markdownlint-cli2 --fix --config .markdownlint.yaml "$TARGET_DIR/**/*.md" || true
echo ""

echo "Step 2: Fixing duplicate H1 headings..."
"$SCRIPT_DIR/fix-duplicate-h1.sh" "$TARGET_DIR"
echo ""

echo "Step 3: Fixing image alt text..."
"$SCRIPT_DIR/fix-image-alt-text.sh" "$TARGET_DIR"
echo ""

echo "Step 4: Fixing bold H1 headings..."
"$SCRIPT_DIR/fix-bold-h1.sh" "$TARGET_DIR"
echo ""

echo "Step 5: Fixing ordered list prefixes..."
"$SCRIPT_DIR/fix-ordered-lists.sh" "$TARGET_DIR"
echo ""

echo "Step 6: Removing emojis..."
uv run "$SCRIPT_DIR/remove-emojis.py" "$TARGET_DIR"
echo ""

echo "Step 7: Re-checking issues..."
markdownlint_output=$(markdownlint-cli2 --config .markdownlint.yaml "$TARGET_DIR/**/*.md" 2>&1)
markdownlint_exit=$?

if [[ $markdownlint_exit -eq 0 ]]; then
    echo "✓ All markdown issues fixed!"
else
    echo "Remaining issues require manual review:"
    echo "$markdownlint_output" | head -20
fi
