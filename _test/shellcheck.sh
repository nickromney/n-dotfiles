#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for --github flag (exit 0 even with issues, like GitHub Actions)
GITHUB_MODE=false
if [[ "${1:-}" == "--github" ]]; then
    GITHUB_MODE=true
fi

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo -e "${RED}Error: ShellCheck is not installed${NC}"
    echo "Please install ShellCheck:"
    echo "  brew install shellcheck      # on macOS"
    echo "  sudo apt-get install shellcheck  # on Ubuntu/Debian"
    echo "  or visit: https://www.shellcheck.net"
    exit 1
fi

# Change to repository root
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo -e "${YELLOW}Running ShellCheck...${NC}"
echo

# Track if any checks fail
any_failed=false

# Function to run shellcheck and count issues
check_file() {
    local file="$1"
    local name="$2"
    
    echo -e "${YELLOW}Checking $name...${NC}"
    if shellcheck "$file" 2>&1 | tee /tmp/shellcheck_output.txt; then
        echo -e "  ${GREEN}✓ No issues found${NC}"
    else
        local error_count=$(grep -c "error" /tmp/shellcheck_output.txt || true)
        local warning_count=$(grep -c "warning" /tmp/shellcheck_output.txt || true)
        local info_count=$(grep -c "info" /tmp/shellcheck_output.txt || true)
        
        if [[ $error_count -gt 0 ]]; then
            echo -e "  ${RED}✗ Found $error_count errors${NC}"
            any_failed=true
        elif [[ $warning_count -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠ Found $warning_count warnings${NC}"
            any_failed=true
        else
            echo -e "  ${YELLOW}ℹ Found $info_count info messages${NC}"
            # Don't fail on info messages
        fi
    fi
}

# Check all files
check_file "install.sh" "install.sh"
echo
check_file "_test/install.bats" "install.bats" 
echo
check_file "_test/macos.bats" "macos.bats"
echo
check_file "_test/helpers/mocks.bash" "helpers/mocks.bash"
echo
check_file "_macos/macos.sh" "macos.sh"

# Summary
echo
if [ "$any_failed" = true ]; then
    echo -e "${RED}ShellCheck found issues!${NC}"
    if [ "$GITHUB_MODE" = true ]; then
        echo -e "${YELLOW}(Continuing anyway in GitHub mode)${NC}"
        exit 0
    else
        exit 1
    fi
else
    echo -e "${GREEN}All ShellCheck tests passed!${NC}"
    exit 0
fi