#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo -e "${RED}Error: BATS is not installed${NC}"
    echo "Please install BATS:"
    echo "  brew install bats-core  # on macOS"
    echo "  or visit: https://github.com/bats-core/bats-core"
    exit 1
fi

# Change to test directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Run tests
echo -e "${YELLOW}Running BATS tests...${NC}"
echo

# Run all .bats files
all_passed=true
for test_file in *.bats; do
    echo -e "${YELLOW}Running $test_file...${NC}"
    if ! bats "$test_file"; then
        all_passed=false
    fi
    echo
done

if [ "$all_passed" = true ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi