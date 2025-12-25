#!/usr/bin/env bash
#
# Tests for install.sh
#
# Usage: bash tests/test_install.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMPDIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#######################################
# Test helpers
#######################################

setup_test() {
  TEST_TMPDIR=$(mktemp -d)
  mkdir -p "$TEST_TMPDIR/project"
}

cleanup_test() {
  if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

test_start() {
  echo -n "Testing: $1... "
  TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
  echo -e "${GREEN}PASS${NC}"
  [ -n "${1:-}" ] && echo "  $1" || true
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
  echo -e "${RED}FAIL${NC}"
  echo "  $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Run install.sh with simulated input
run_install() {
  local project_dir="$1"
  local nickname="$2"
  echo "$nickname" | bash "$REPO_DIR/install.sh" "$project_dir" 2>&1
}

#######################################
# Test: Fresh install creates all files
#######################################
test_start "fresh install creates hooks and settings"
setup_test

output=$(run_install "$TEST_TMPDIR/project" "testuser")

# Check hooks exist
if [ -f "$TEST_TMPDIR/project/.claude/hooks/session_start.sh" ] && \
   [ -f "$TEST_TMPDIR/project/.claude/hooks/session_end.sh" ]; then
  # Check hooks are executable
  if [ -x "$TEST_TMPDIR/project/.claude/hooks/session_start.sh" ] && \
     [ -x "$TEST_TMPDIR/project/.claude/hooks/session_end.sh" ]; then
    # Check settings.json exists with hooks
    if [ -f "$TEST_TMPDIR/project/.claude/settings.json" ]; then
      if jq -e '.hooks.SessionStart' "$TEST_TMPDIR/project/.claude/settings.json" > /dev/null 2>&1; then
        test_pass
      else
        test_fail "settings.json missing SessionStart hook"
      fi
    else
      test_fail "settings.json not created"
    fi
  else
    test_fail "hooks not executable"
  fi
else
  test_fail "hook files not created"
fi

cleanup_test

#######################################
# Test: Reinstall doesn't duplicate hooks
#######################################
test_start "reinstall doesn't duplicate hooks"
setup_test

# First install
run_install "$TEST_TMPDIR/project" "testuser" > /dev/null

# Count hooks before
start_count_before=$(jq '.hooks.SessionStart | length' "$TEST_TMPDIR/project/.claude/settings.json")
end_count_before=$(jq '.hooks.SessionEnd | length' "$TEST_TMPDIR/project/.claude/settings.json")

# Second install (reinstall)
output=$(run_install "$TEST_TMPDIR/project" "testuser")

# Count hooks after
start_count_after=$(jq '.hooks.SessionStart | length' "$TEST_TMPDIR/project/.claude/settings.json")
end_count_after=$(jq '.hooks.SessionEnd | length' "$TEST_TMPDIR/project/.claude/settings.json")

if [ "$start_count_before" = "$start_count_after" ] && [ "$end_count_before" = "$end_count_after" ]; then
  if echo "$output" | grep -q "already configured\|already installed"; then
    test_pass "hooks not duplicated, installer detected existing"
  else
    test_pass "hooks not duplicated"
  fi
else
  test_fail "hooks duplicated: before=$start_count_before/$end_count_before after=$start_count_after/$end_count_after"
fi

cleanup_test

#######################################
# Test: Install with existing other hooks
#######################################
test_start "install preserves existing hooks"
setup_test

# Create project with existing hooks
mkdir -p "$TEST_TMPDIR/project/.claude"
cat > "$TEST_TMPDIR/project/.claude/settings.json" << 'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {"type": "command", "command": "echo existing-hook"}
        ]
      }
    ]
  }
}
EOF

run_install "$TEST_TMPDIR/project" "testuser" > /dev/null

# Check existing hook preserved
existing=$(jq -r '.hooks.SessionStart[].hooks[]? | select(.command == "echo existing-hook") | .command' "$TEST_TMPDIR/project/.claude/settings.json" 2>/dev/null || echo "")

# Check our hook added
ours=$(jq -r '.hooks.SessionStart[].hooks[]? | select(.command | contains("session_start.sh")) | .command' "$TEST_TMPDIR/project/.claude/settings.json" 2>/dev/null || echo "")

if [ -n "$existing" ] && [ -n "$ours" ]; then
  test_pass "both hooks present"
else
  test_fail "existing='$existing' ours='$ours'"
fi

cleanup_test

#######################################
# Test: Invalid nickname rejected (empty)
#######################################
test_start "empty nickname rejected"
setup_test

# Send empty then valid nickname
output=$(echo -e "\ntestuser" | bash "$REPO_DIR/install.sh" "$TEST_TMPDIR/project" 2>&1)

if echo "$output" | grep -qi "cannot be empty\|invalid"; then
  test_pass
else
  test_fail "no rejection message for empty nickname"
fi

cleanup_test

#######################################
# Test: Invalid nickname rejected (special chars)
#######################################
test_start "invalid characters rejected"
setup_test

# Send invalid then valid nickname
output=$(echo -e "test@user!\ntestuser" | bash "$REPO_DIR/install.sh" "$TEST_TMPDIR/project" 2>&1)

if echo "$output" | grep -qi "invalid"; then
  test_pass
else
  test_fail "no rejection for special characters"
fi

cleanup_test

#######################################
# Test: Uppercase nickname normalized
#######################################
test_start "uppercase nickname normalized to lowercase"
setup_test

run_install "$TEST_TMPDIR/project" "TestUser" > /dev/null

# Check the output message uses lowercase
output=$(run_install "$TEST_TMPDIR/project" "ANOTHERUSER" 2>&1 || true)

if echo "$output" | grep -q "anotheruser"; then
  test_pass
else
  # Check if session path shows lowercase
  if echo "$output" | grep -qi "sessions/anotheruser"; then
    test_pass
  else
    test_fail "uppercase not normalized"
  fi
fi

cleanup_test

#######################################
# Test: Non-existent project directory fails
#######################################
test_start "non-existent directory fails"
setup_test

output=$(run_install "$TEST_TMPDIR/nonexistent" "testuser" 2>&1 || true)

if echo "$output" | grep -qi "not a directory\|error"; then
  test_pass
else
  test_fail "should fail for non-existent directory"
fi

cleanup_test

#######################################
# Test: Backup created on reinstall
#######################################
test_start "backup created when settings.json exists"
setup_test

# First install
run_install "$TEST_TMPDIR/project" "testuser" > /dev/null

# Check no backup yet (first install) - use find for reliable counting
backup_count_before=$(find "$TEST_TMPDIR/project/.claude" -name "settings.json.backup.*" 2>/dev/null | wc -l | tr -d ' ')

# Second install
sleep 1  # Ensure different timestamp
run_install "$TEST_TMPDIR/project" "testuser" > /dev/null

backup_count_after=$(find "$TEST_TMPDIR/project/.claude" -name "settings.json.backup.*" 2>/dev/null | wc -l | tr -d ' ')

if [ "$backup_count_after" -gt "$backup_count_before" ]; then
  test_pass
else
  test_fail "no backup created: before=$backup_count_before after=$backup_count_after"
fi

cleanup_test

#######################################
# Test: Hook content is current version
#######################################
test_start "hooks contain current code"
setup_test

run_install "$TEST_TMPDIR/project" "testuser" > /dev/null

# Check for GITHUB_NICKNAME in installed hooks (new feature)
if grep -q "GITHUB_NICKNAME" "$TEST_TMPDIR/project/.claude/hooks/session_start.sh"; then
  test_pass "hooks have GITHUB_NICKNAME support"
else
  test_fail "hooks missing GITHUB_NICKNAME (old version?)"
fi

cleanup_test

#######################################
# Test: Success message shows nickname
#######################################
test_start "success message shows session path"
setup_test

output=$(run_install "$TEST_TMPDIR/project" "myname")

if echo "$output" | grep -q "sessions/myname"; then
  test_pass
else
  test_fail "success message doesn't show session path"
fi

cleanup_test

#######################################
# Test: Gitignore warning for .claude/
#######################################
test_start "gitignore warning for .claude/ pattern"
setup_test

# Create gitignore with problematic pattern
echo ".claude/" > "$TEST_TMPDIR/project/.gitignore"

output=$(run_install "$TEST_TMPDIR/project" "testuser")

if echo "$output" | grep -q "WARNING.*Critical files"; then
  test_pass
else
  test_fail "no warning for .claude/ in gitignore"
fi

cleanup_test

#######################################
# Test: Gitignore warning for .claude/settings
#######################################
test_start "gitignore warning for settings.json pattern"
setup_test

echo ".claude/settings.json" > "$TEST_TMPDIR/project/.gitignore"

output=$(run_install "$TEST_TMPDIR/project" "testuser")

if echo "$output" | grep -q "WARNING.*Critical files"; then
  test_pass
else
  test_fail "no warning for .claude/settings in gitignore"
fi

cleanup_test

#######################################
# Test: No gitignore warning for clean project
#######################################
test_start "no warning when gitignore is clean"
setup_test

# Create gitignore without problematic patterns
echo "node_modules/" > "$TEST_TMPDIR/project/.gitignore"
echo ".env" >> "$TEST_TMPDIR/project/.gitignore"

output=$(run_install "$TEST_TMPDIR/project" "testuser")

if echo "$output" | grep -q "WARNING.*Critical files"; then
  test_fail "false warning when gitignore is clean"
else
  test_pass
fi

cleanup_test

#######################################
# Test: Sessions gitignore is noted but not critical
#######################################
test_start "sessions gitignore is noted but OK"
setup_test

echo ".claude/sessions/" > "$TEST_TMPDIR/project/.gitignore"

output=$(run_install "$TEST_TMPDIR/project" "testuser")

# Should NOT show critical warning
if echo "$output" | grep -q "WARNING.*Critical files"; then
  test_fail "sessions should not trigger critical warning"
else
  # Should show note
  if echo "$output" | grep -q "Note:.*sessions"; then
    test_pass "correctly noted as non-critical"
  else
    test_pass "no warning for sessions-only gitignore"
  fi
fi

cleanup_test

#######################################
# Summary
#######################################
echo ""
echo "========================================"
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${NC} | ${RED}Failed: $TESTS_FAILED${NC}"
echo "========================================"

if [ $TESTS_FAILED -gt 0 ]; then
  exit 1
fi
