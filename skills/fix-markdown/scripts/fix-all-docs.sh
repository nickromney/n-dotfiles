#!/usr/bin/env bash
#
# Fix all auto-fixable markdown issues in documentation
#
# Usage: ./fix-all-docs.sh [directory]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-documentation}"

# Use local config if present, otherwise fall back to skill's bundled config
if [[ -f .markdownlint.yaml ]]; then
    MARKDOWNLINT_CONFIG=".markdownlint.yaml"
elif [[ -f "$SCRIPT_DIR/../.markdownlint.yaml" ]]; then
    MARKDOWNLINT_CONFIG="$SCRIPT_DIR/../.markdownlint.yaml"
else
    echo "Warning: No .markdownlint.yaml found, using markdownlint-cli2 defaults"
    MARKDOWNLINT_CONFIG=""
fi

echo "Fixing markdown issues in: $TARGET_DIR"
[[ -n "$MARKDOWNLINT_CONFIG" ]] && echo "Using config: $MARKDOWNLINT_CONFIG"
echo ""

echo "Step 1: Running markdownlint auto-fix..."
if [[ -n "$MARKDOWNLINT_CONFIG" ]]; then
    find "$TARGET_DIR" -name '*.md' -print0 | xargs -0 markdownlint-cli2 --fix --config "$MARKDOWNLINT_CONFIG" || true
else
    find "$TARGET_DIR" -name '*.md' -print0 | xargs -0 markdownlint-cli2 --fix || true
fi
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
uv run "$SCRIPT_DIR/detect-emojis.py" --remove "$TARGET_DIR"
echo ""

echo "Step 7: Re-checking issues..."
if [[ -n "$MARKDOWNLINT_CONFIG" ]]; then
    markdownlint_output=$(find "$TARGET_DIR" -name '*.md' -print0 | xargs -0 markdownlint-cli2 --config "$MARKDOWNLINT_CONFIG" 2>&1)
else
    markdownlint_output=$(find "$TARGET_DIR" -name '*.md' -print0 | xargs -0 markdownlint-cli2 2>&1)
fi
markdownlint_exit=$?

if [[ $markdownlint_exit -eq 0 ]]; then
    echo "✓ All markdown issues fixed!"
else
    echo "Remaining issues require manual review:"
    echo "$markdownlint_output" | head -20
fi
