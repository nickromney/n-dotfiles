#!/usr/bin/env bash
#
# Report markdown linting issues grouped by file and type
#
# Usage: ./report-markdownlint-issues.sh [directory]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-documentation}"
TEMP_FILE="/tmp/markdownlint-report.$$"

# Use local config if present, otherwise fall back to skill's bundled config
if [[ -f .markdownlint.yaml ]]; then
    MARKDOWNLINT_CONFIG=".markdownlint.yaml"
elif [[ -f "$SCRIPT_DIR/../.markdownlint.yaml" ]]; then
    MARKDOWNLINT_CONFIG="$SCRIPT_DIR/../.markdownlint.yaml"
else
    echo "Warning: No .markdownlint.yaml found, using markdownlint-cli2 defaults"
    MARKDOWNLINT_CONFIG=""
fi

echo "Markdown Linting Report for: $TARGET_DIR"
[[ -n "$MARKDOWNLINT_CONFIG" ]] && echo "Using config: $MARKDOWNLINT_CONFIG"
echo "=========================================="
echo ""

# Run markdownlint and save to temp file
if [[ -n "$MARKDOWNLINT_CONFIG" ]]; then
    find "$TARGET_DIR" -name '*.md' -print0 | xargs -0 markdownlint-cli2 --config "$MARKDOWNLINT_CONFIG" > "$TEMP_FILE" 2>&1 || true
else
    find "$TARGET_DIR" -name '*.md' -print0 | xargs -0 markdownlint-cli2 > "$TEMP_FILE" 2>&1 || true
fi

# Check if there are any issues
if [[ ! -s "$TEMP_FILE" ]]; then
    echo "✓ No markdown linting issues found!"
    rm -f "$TEMP_FILE"
    exit 0
fi

# Get total count
total_issues=$(wc -l < "$TEMP_FILE" | tr -d ' ')
echo "Total issues: $total_issues"
echo ""

# Breakdown by issue type
echo "Issues by Type:"
echo "---------------"
awk '{print $2}' "$TEMP_FILE" | \
    sort | \
    uniq -c | \
    sort -rn | \
    awk '{printf "  %3d  %s\n", $1, $2}'
echo ""

# Files with issues
echo "Files Requiring Manual Intervention:"
echo "-------------------------------------"
cut -d':' -f1 "$TEMP_FILE" | \
    sort | \
    uniq -c | \
    sort -rn | \
    awk '{printf "  %2d issues: %s\n", $1, $2}'
echo ""

# Full details
echo "Detailed Issues:"
echo "----------------"
cat "$TEMP_FILE"

# Cleanup
rm -f "$TEMP_FILE"
