#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo -e "${RED}Error: shellcheck is not installed${NC}"
    echo "Please install shellcheck:"
    echo "  brew install shellcheck  # on macOS"
    echo "  apt-get install shellcheck  # on Ubuntu/Debian"
    exit 1
fi

# Change to repository root
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo -e "${BLUE}Running shellcheck on shell scripts...${NC}"
echo

any_failed=false

# Function to check a file
check_file() {
    local file="$1"
    local name="$2"

    echo -e "${YELLOW}Checking $name...${NC}"
    if shellcheck "$file" 2>&1 | tee /tmp/shellcheck_output.txt; then
        echo -e "  ${GREEN}✓ No issues found${NC}"
    else
        local error_count
        local warning_count
        local info_count
        error_count=$(grep -c "error" /tmp/shellcheck_output.txt || true)
        warning_count=$(grep -c "warning" /tmp/shellcheck_output.txt || true)
        info_count=$(grep -c "info" /tmp/shellcheck_output.txt || true)

        if [[ $error_count -gt 0 ]]; then
            echo -e "  ${RED}✗ Found $error_count errors${NC}"
            any_failed=true
        elif [[ $warning_count -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠ Found $warning_count warnings${NC}"
            any_failed=true
        else
            echo -e "  ${YELLOW}ℹ Found $info_count info messages${NC}"
        fi
    fi
    echo
}

# Check main scripts
check_file "install.sh" "install.sh"
check_file "_macos/macos.sh" "_macos/macos.sh"

# Check setup scripts at root
for script in setup-*.sh; do
    if [[ -f "$script" ]]; then
        check_file "$script" "$script"
    fi
done

# Check test scripts
echo -e "${YELLOW}Checking test scripts...${NC}"
for script in _test/*.sh; do
    if [[ -f "$script" ]]; then
        check_file "$script" "$script"
    fi
done

# Check BATS test files
echo -e "${YELLOW}Checking BATS test files...${NC}"
for bats_file in _test/*.bats; do
    if [[ -f "$bats_file" ]]; then
        check_file "$bats_file" "$bats_file"
    fi
done

# Check helper files
echo -e "${YELLOW}Checking test helper files...${NC}"
for helper in _test/helpers/*.bash; do
    if [[ -f "$helper" ]]; then
        check_file "$helper" "$helper"
    fi
done

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [[ "$any_failed" == "true" ]]; then
    echo -e "${RED}✗ Some files have shellcheck issues${NC}"
    echo -e "${YELLOW}Fix the issues above and run this script again${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All files passed shellcheck${NC}"
    exit 0
fi
