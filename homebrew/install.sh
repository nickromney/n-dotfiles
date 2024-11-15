#!/bin/bash
set -euo pipefail

BREWLEAVES_FILE="brewleaves.txt"

if ! command -v uv &> /dev/null; then
  echo "uv is not installed. Please install uv first."
  echo "Check instructions at https://github.com/astral-sh/uv"
fi

uv tool install --python 3.12 posting

# check if homebrew is installed
if ! command -v brew &> /dev/null; then
  echo "Homebrew is not installed. Please install Homebrew first."
  echo "Check instructions at https://brew.sh"
  exit 1
fi

# check for existence of brewleaves.txt
if [ ! -f "${BREWLEAVES_FILE}" ]; then
  echo "${BREWLEAVES_FILE} not found. Please create a list of packages to install."
  exit 1
fi

xargs brew install < ${BREWLEAVES_FILE}