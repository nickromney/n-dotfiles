#!/usr/bin/env python3
"""Detect and optionally remove emojis from markdown files.

Usage:
    ./detect-emojis.py <file-or-directory>           # Detect only (exit 1 if found)
    ./detect-emojis.py --remove <file-or-directory>  # Remove emojis
"""

import argparse
import re
import sys
from pathlib import Path


# Emoji regex pattern covering common ranges
EMOJI_PATTERN = re.compile(
    "["
    "\U0001F300-\U0001FAF6"  # Emoticons & symbols
    "\U00002600-\U000026FF"  # Misc symbols
    "\U00002700-\U000027BF"  # Dingbats
    "\U00002B00-\U00002BFF"  # Misc symbols and pictographs (includes stars)
    "\U0000231A-\U000023FF"  # Misc technical
    "\U0000FE00-\U0000FE0F"  # Variation selectors
    "]+",
    flags=re.UNICODE,
)


def remove_emojis(text: str) -> str:
    """Remove all emoji characters from text."""
    text = EMOJI_PATTERN.sub("", text)
    text = re.sub(r"  +", " ", text)
    return text


def detect_emojis(file_path: Path) -> bool:
    """Check if file contains emojis, return True if found."""
    content = file_path.read_text(encoding="utf-8")
    return bool(EMOJI_PATTERN.search(content))


def process_file_detect(file_path: Path) -> bool:
    """Detect emojis in a single file, return True if found."""
    if detect_emojis(file_path):
        print(f"Found emojis: {file_path}")
        return True
    return False


def process_file_remove(file_path: Path) -> bool:
    """Remove emojis from a single file, return True if modified."""
    content = file_path.read_text(encoding="utf-8")
    cleaned = remove_emojis(content)

    if content != cleaned:
        file_path.write_text(cleaned, encoding="utf-8")
        print(f"Removed emojis: {file_path}")
        return True

    return False


def main():
    parser = argparse.ArgumentParser(
        description="Detect and optionally remove emojis from markdown files"
    )
    parser.add_argument(
        "target",
        type=Path,
        help="File or directory to process"
    )
    parser.add_argument(
        "--remove",
        action="store_true",
        help="Remove emojis (default: detect only)"
    )

    args = parser.parse_args()

    if not args.target.exists():
        print(f"Error: {args.target} does not exist")
        sys.exit(1)

    found_emojis = False
    process_func = process_file_remove if args.remove else process_file_detect

    if args.target.is_file():
        found_emojis = process_func(args.target)
    elif args.target.is_dir():
        for md_file in args.target.rglob("*.md"):
            if process_func(md_file):
                found_emojis = True
    else:
        print(f"Error: {args.target} is not a file or directory")
        sys.exit(1)

    # Exit with error code if emojis found (in detect mode)
    if not args.remove and found_emojis:
        print("\nEmojis detected! Run with --remove to fix automatically.")
        sys.exit(1)

    if not args.remove and not found_emojis:
        print("No emojis found.")


if __name__ == "__main__":
    main()
