#!/usr/bin/env bash
#
# Simple TAP-compatible test runner for Claude Tracker hooks
# No external dependencies required
#

set -o pipefail

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  GREEN=''
  RED=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Current test context
CURRENT_TEST=""
TEST_TMPDIR=""

#######################################
# Test framework functions
#######################################

# Setup test environment
setup_test_env() {
  TEST_TMPDIR=$(mktemp -d)
  mkdir -p "$TEST_TMPDIR/.claude/sessions"
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  mkdir -p "$TEST_TMPDIR/.claude/skills/test-skill"
  mkdir -p "$TEST_TMPDIR/.claude/commands"

  # Copy hooks to test directory
  cp "$(dirname "$0")/../session_start.sh" "$TEST_TMPDIR/.claude/hooks/"
  cp "$(dirname "$0")/../session_end.sh" "$TEST_TMPDIR/.claude/hooks/"
  chmod +x "$TEST_TMPDIR/.claude/hooks/"*.sh
}

# Cleanup test environment
cleanup_test_env() {
  if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# Start a test
test_start() {
  CURRENT_TEST="$1"
  ((TESTS_RUN++))
  echo -e "${BLUE}Running:${NC} $CURRENT_TEST"
}

# Pass a test
test_pass() {
  local msg="${1:-}"
  ((TESTS_PASSED++))
  echo -e "  ${GREEN}✓ PASS${NC}${msg:+: $msg}"
}

# Fail a test
test_fail() {
  local msg="${1:-}"
  ((TESTS_FAILED++))
  echo -e "  ${RED}✗ FAIL${NC}${msg:+: $msg}"
}

# Skip a test
test_skip() {
  local msg="${1:-}"
  ((TESTS_SKIPPED++))
  echo -e "  ${YELLOW}○ SKIP${NC}${msg:+: $msg}"
}

# Assert that a condition is true
assert() {
  local condition="$1"
  local msg="${2:-Assertion failed}"

  if eval "$condition"; then
    return 0
  else
    test_fail "$msg"
    return 1
  fi
}

# Assert that two values are equal
assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-Expected '$expected' but got '$actual'}"

  if [ "$expected" = "$actual" ]; then
    return 0
  else
    test_fail "$msg"
    return 1
  fi
}

# Assert that a file exists
assert_file_exists() {
  local file="$1"
  local msg="${2:-File should exist: $file}"

  if [ -f "$file" ]; then
    return 0
  else
    test_fail "$msg"
    return 1
  fi
}

# Assert that JSON has a specific value
assert_json_value() {
  local file="$1"
  local jq_path="$2"
  local expected="$3"
  local msg="${4:-JSON value mismatch}"

  local actual
  actual=$(jq -r "$jq_path" "$file" 2>/dev/null)

  if [ "$expected" = "$actual" ]; then
    return 0
  else
    test_fail "$msg (expected '$expected', got '$actual')"
    return 1
  fi
}

# Assert that JSON path exists and is not null
assert_json_exists() {
  local file="$1"
  local jq_path="$2"
  local msg="${3:-JSON path should exist: $jq_path}"

  if jq -e "$jq_path" "$file" &>/dev/null; then
    return 0
  else
    test_fail "$msg"
    return 1
  fi
}

# Run a hook with input
run_hook() {
  local hook="$1"
  local input="$2"

  echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/$hook"
}

# Print test summary
print_summary() {
  echo ""
  echo "================================"
  echo "Test Summary"
  echo "================================"
  echo -e "Total:   $TESTS_RUN"
  echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
  echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
  echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
  echo "================================"

  if [ "$TESTS_FAILED" -gt 0 ]; then
    return 1
  fi
  return 0
}

#######################################
# Run all tests
#######################################

main() {
  echo "Claude Tracker Hook Tests"
  echo "========================="
  echo ""

  # Check dependencies
  if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq is required to run tests${NC}"
    exit 1
  fi

  # Find and run all test files
  local test_dir
  test_dir="$(dirname "$0")"

  for test_file in "$test_dir"/test_*.sh; do
    [ -f "$test_file" ] || continue
    [ "$test_file" = "$0" ] && continue  # Skip self

    echo ""
    echo "Loading: $(basename "$test_file")"
    echo "---"

    # Source the test file (it defines test functions)
    source "$test_file"
  done

  echo ""
  print_summary
}

# Export functions for test files
export -f setup_test_env cleanup_test_env
export -f test_start test_pass test_fail test_skip
export -f assert assert_equals assert_file_exists
export -f assert_json_value assert_json_exists
export -f run_hook

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
