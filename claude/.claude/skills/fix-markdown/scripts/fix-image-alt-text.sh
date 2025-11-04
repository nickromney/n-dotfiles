#!/usr/bin/env bash
#
# Fix MD045: Add descriptive alt text to images
#
# Usage: ./fix-image-alt-text.sh [file or directory]
#

set -euo pipefail

# Detect platform for sed in-place editing
if [[ "$(uname)" == "Darwin" ]]; then
    SED_INPLACE=(-i '')
else
    SED_INPLACE=(-i)
fi

fix_file() {
    local file=$1
    local changed=false

    # Add "Image" as alt text for images with empty alt text
    if grep -qE '!\[\]\(' "$file"; then
        sed "${SED_INPLACE[@]}" 's/!\[\](\([^)]*\))/![Image](\1)/g' "$file"
        changed=true
    fi

    if [[ "$changed" == "true" ]]; then
        echo "Fixed: $file"
    fi
}

if [[ -d "${1:-}" ]]; then
    find "$1" -name "*.md" -type f | while read -r file; do
        fix_file "$file"
    done
elif [[ -f "${1:-}" ]]; then
    fix_file "$1"
else
    echo "Usage: $0 <file-or-directory>"
    exit 1
fi
