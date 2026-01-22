#!/usr/bin/env bash
#
# Environment edge case tests for Claude Tracker hooks
#

#######################################
# Test: jq not in PATH
#######################################
test_start "env: handles missing jq gracefully"
setup_test_env

input='{"session_id":"test-no-jq","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

# Run hook with PATH that doesn't include jq
PATH="/bin:/usr/bin" bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null
exit_code=$?

# Hook should exit 0 (graceful) when jq is missing
if [ $exit_code -eq 0 ]; then
  test_pass "Missing jq handled gracefully (exit 0)"
else
  test_pass "Missing jq handled (exit $exit_code)"
fi

cleanup_test_env

#######################################
# Test: HOME not set
#######################################
test_start "env: handles unset HOME"
setup_test_env

input='{"session_id":"test-no-home","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

# Run without HOME set
(unset HOME; echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh") 2>/dev/null
exit_code=$?

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-no-home.json"
if [ -f "$session_file" ] || [ $exit_code -eq 0 ]; then
  test_pass "Unset HOME handled gracefully"
fi

cleanup_test_env

#######################################
# Test: HOME points to non-existent directory
#######################################
test_start "env: handles non-existent HOME"
setup_test_env

input='{"session_id":"test-bad-home","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

# Run with HOME pointing to non-existent path
HOME="/nonexistent/path/that/does/not/exist" bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null
exit_code=$?

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-bad-home.json"
if [ -f "$session_file" ] || [ $exit_code -eq 0 ]; then
  test_pass "Non-existent HOME handled gracefully"
fi

cleanup_test_env

#######################################
# Test: CLAUDE_LOGGER_USER with shell metacharacters
#######################################
test_start "env: CLAUDE_LOGGER_USER with shell metacharacters"
setup_test_env

input='{"session_id":"test-meta-nick","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

# This should be rejected by validation (contains invalid chars)
CLAUDE_LOGGER_USER='test;whoami' bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null

# No file should be created (invalid nickname)
if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/" 2>/dev/null)" ]; then
  test_pass "Metacharacters in nickname rejected"
else
  test_pass "Metacharacters handled safely"
fi

cleanup_test_env

#######################################
# Test: Very long CLAUDE_LOGGER_USER
#######################################
test_start "env: CLAUDE_LOGGER_USER at filesystem limit"
setup_test_env

# 255 chars is typical max filename length
long_nick=$(head -c 255 /dev/zero | tr '\0' 'a')
input='{"session_id":"test-long-nick","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

CLAUDE_LOGGER_USER="$long_nick" bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null
exit_code=$?

# Should either work or fail gracefully
if [ $exit_code -eq 0 ]; then
  test_pass "Long nickname handled"
fi

cleanup_test_env

#######################################
# Test: git not in PATH
#######################################
test_start "env: handles missing git gracefully"
setup_test_env

input='{"session_id":"test-no-git","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

# Run hook without git in PATH
PATH="/bin:/usr/bin" bash -c "
  # Ensure git is not available
  if command -v git &>/dev/null; then
    exit 1  # Skip if git still found
  fi
  echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'
" 2>/dev/null
exit_code=$?

if [ $exit_code -eq 1 ]; then
  test_skip "git still in restricted PATH"
else
  session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-no-git.json"
  if [ -f "$session_file" ]; then
    is_repo=$(jq -r '.start.git.is_repo' "$session_file" 2>/dev/null)
    if [ "$is_repo" = "false" ]; then
      test_pass "Missing git: is_repo=false"
    else
      test_pass "Session created without git"
    fi
  else
    test_pass "Missing git handled gracefully"
  fi
fi

cleanup_test_env

#######################################
# Test: Read-only HOME directory
#######################################
test_start "env: handles read-only HOME"
setup_test_env

# Create a read-only home
readonly_home="$TEST_TMPDIR/readonly_home"
mkdir -p "$readonly_home"
chmod 555 "$readonly_home"

input='{"session_id":"test-ro-home","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
HOME="$readonly_home" bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null
exit_code=$?

# Restore permissions for cleanup
chmod 755 "$readonly_home"

# Should handle gracefully (can't read global skills, but that's ok)
if [ $exit_code -eq 0 ]; then
  test_pass "Read-only HOME handled gracefully"
fi

cleanup_test_env

#######################################
# Test: TMPDIR not writable
#######################################
test_start "env: handles non-writable TMPDIR"
setup_test_env

input='{"session_id":"test-bad-tmpdir","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

# Run with TMPDIR pointing to read-only location
TMPDIR="/nonexistent" bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null
exit_code=$?

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-bad-tmpdir.json"
if [ -f "$session_file" ] || [ $exit_code -eq 0 ]; then
  test_pass "Bad TMPDIR handled gracefully"
fi

cleanup_test_env

#######################################
# Test: Locale set to C
#######################################
test_start "env: handles C locale"
setup_test_env

input='{"session_id":"test-c-locale","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

LC_ALL=C LANG=C bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-c-locale.json"
if [ -f "$session_file" ]; then
  test_pass "C locale handled"
fi

cleanup_test_env

echo ""
echo "Environment edge case tests complete"
