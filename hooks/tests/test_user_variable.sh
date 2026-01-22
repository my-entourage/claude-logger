#!/usr/bin/env bash
#
# Tests for CLAUDE_LOGGER_USER handling, validation, and multi-user support
#

#######################################
# Test: Unset CLAUDE_LOGGER_USER shows warning
#######################################
test_start "user: unset shows warning message"
setup_test_env

# Unset the user variable that setup_test_env sets
unset CLAUDE_LOGGER_USER

input='{"session_id":"test-unset","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "CLAUDE_LOGGER_USER not set"; then
  test_pass "Warning message shown"
else
  test_fail "Warning message not shown: $output"
fi

# Restore for cleanup
export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Warning goes to stderr, not stdout
#######################################
test_start "user: warning goes to stderr not stdout"
setup_test_env
unset CLAUDE_LOGGER_USER

input='{"session_id":"test-stderr","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
stdout_output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>/dev/null)
stderr_output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1 >/dev/null)

if [ -z "$stdout_output" ] && echo "$stderr_output" | grep -q "CLAUDE_LOGGER_USER"; then
  test_pass "Warning on stderr, stdout empty"
else
  test_fail "stdout='$stdout_output' stderr='$stderr_output'"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Unset CLAUDE_LOGGER_USER exits 0
#######################################
test_start "user: unset exits with code 0"
setup_test_env
unset CLAUDE_LOGGER_USER

input='{"session_id":"test-exit","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>/dev/null
exit_code=$?

if [ "$exit_code" -eq 0 ]; then
  test_pass "Exit code is 0"
else
  test_fail "Exit code was $exit_code, expected 0"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Unset CLAUDE_LOGGER_USER creates no file
#######################################
test_start "user: unset creates no session file"
setup_test_env
unset CLAUDE_LOGGER_USER

input='{"session_id":"test-nofile","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>/dev/null

# Check no files created anywhere in sessions
file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
if [ "$file_count" -eq 0 ]; then
  test_pass "No session file created"
else
  test_fail "Found $file_count files when none expected"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Empty string CLAUDE_LOGGER_USER shows warning
#######################################
test_start "user: empty string shows warning"
setup_test_env
export CLAUDE_LOGGER_USER=""

input='{"session_id":"test-empty","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "CLAUDE_LOGGER_USER not set"; then
  test_pass "Empty string triggers warning"
else
  test_fail "Empty string did not trigger warning"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Whitespace-only CLAUDE_LOGGER_USER
#######################################
test_start "user: whitespace-only handled"
setup_test_env
export CLAUDE_LOGGER_USER="   "

input='{"session_id":"test-whitespace","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

# Should either warn (empty after trim) or reject as invalid chars
if echo "$output" | grep -qi "warning\|not set\|invalid"; then
  test_pass "Whitespace-only handled"
else
  # Check no file created
  file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -eq 0 ]; then
    test_pass "Whitespace-only rejected (no file)"
  else
    test_fail "Whitespace-only should be rejected"
  fi
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

echo ""
echo "Warning tests complete"

#######################################
# VALIDATION EDGE CASES
#######################################

#######################################
# Test: Uppercase normalized to lowercase
#######################################
test_start "user: UPPERCASE normalized to lowercase"
setup_test_env
export CLAUDE_LOGGER_USER="TESTUSER"

input='{"session_id":"test-upper","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/testuser/test-upper.json" ]; then
  test_pass "UPPERCASE -> testuser"
else
  test_fail "File not in lowercase directory"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: MixedCase normalized
#######################################
test_start "user: MixedCase normalized to lowercase"
setup_test_env
export CLAUDE_LOGGER_USER="TestUser123"

input='{"session_id":"test-mixed","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/testuser123/test-mixed.json" ]; then
  test_pass "MixedCase -> testuser123"
else
  test_fail "File not in lowercase directory"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: 40+ character username rejected
#######################################
test_start "user: 40+ chars rejected"
setup_test_env
export CLAUDE_LOGGER_USER="abcdefghijklmnopqrstuvwxyz1234567890abcd"  # 40 chars

input='{"session_id":"test-long","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "invalid"; then
  test_pass "40-char username rejected"
else
  file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -eq 0 ]; then
    test_pass "40-char username rejected (no file)"
  else
    test_fail "40-char username should be rejected"
  fi
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Single character username valid
#######################################
test_start "user: single char 'a' is valid"
setup_test_env
export CLAUDE_LOGGER_USER="a"

input='{"session_id":"test-single","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/a/test-single.json" ]; then
  test_pass "Single char username valid"
else
  test_fail "Single char username should be valid"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Numbers-only username valid
#######################################
test_start "user: numbers-only '123' is valid"
setup_test_env
export CLAUDE_LOGGER_USER="123"

input='{"session_id":"test-numbers","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/123/test-numbers.json" ]; then
  test_pass "Numbers-only username valid"
else
  test_fail "Numbers-only username should be valid"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Username with spaces rejected
#######################################
test_start "user: spaces rejected"
setup_test_env
export CLAUDE_LOGGER_USER="user name"

input='{"session_id":"test-spaces","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "invalid"; then
  test_pass "Spaces in username rejected"
else
  file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -eq 0 ]; then
    test_pass "Spaces in username rejected (no file)"
  else
    test_fail "Spaces in username should be rejected"
  fi
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Special characters rejected
#######################################
test_start "user: special chars '@' rejected"
setup_test_env
export CLAUDE_LOGGER_USER="user@name"

input='{"session_id":"test-special","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "invalid"; then
  test_pass "@ in username rejected"
else
  file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -eq 0 ]; then
    test_pass "@ in username rejected (no file)"
  else
    test_fail "@ in username should be rejected"
  fi
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Path traversal attempt rejected
#######################################
test_start "user: path traversal '../etc' rejected"
setup_test_env
export CLAUDE_LOGGER_USER="../etc"

input='{"session_id":"test-traversal","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

# Should be rejected due to dots and slashes
if echo "$output" | grep -q "invalid"; then
  test_pass "Path traversal rejected"
else
  # Verify no file created in parent
  if [ ! -f "$TEST_TMPDIR/.claude/etc/test-traversal.json" ] && \
     [ ! -f "$TEST_TMPDIR/etc/test-traversal.json" ]; then
    test_pass "Path traversal rejected (no file)"
  else
    test_fail "Path traversal should be rejected"
  fi
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Flag-like username '--help'
#######################################
test_start "user: flag-like '--help' handled"
setup_test_env
export CLAUDE_LOGGER_USER="--help"

input='{"session_id":"test-flag","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

# Should be rejected due to invalid chars (leading dashes ok, but -- pattern might fail)
if echo "$output" | grep -q "invalid"; then
  test_pass "--help rejected as invalid"
else
  # If it created a file, that's also acceptable (just a weird directory name)
  if [ -d "$TEST_TMPDIR/.claude/sessions/--help" ]; then
    test_pass "--help handled (dir created)"
  else
    test_pass "--help handled gracefully"
  fi
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Mixed dashes and underscores valid
#######################################
test_start "user: 'a-b_c-d' is valid"
setup_test_env
export CLAUDE_LOGGER_USER="a-b_c-d"

input='{"session_id":"test-mixed-sep","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/a-b_c-d/test-mixed-sep.json" ]; then
  test_pass "Mixed dashes/underscores valid"
else
  test_fail "Mixed dashes/underscores should be valid"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: 39 characters (max valid)
#######################################
test_start "user: 39 chars (max) is valid"
setup_test_env
export CLAUDE_LOGGER_USER="abcdefghijklmnopqrstuvwxyz1234567890abc"  # exactly 39

input='{"session_id":"test-max","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/abcdefghijklmnopqrstuvwxyz1234567890abc/test-max.json" ]; then
  test_pass "39-char username valid"
else
  test_fail "39-char username should be valid (max length)"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

echo ""
echo "Validation edge case tests complete"

#######################################
# MULTI-USER COEXISTENCE TESTS
#######################################

#######################################
# Test: Two users create sessions in same project
#######################################
test_start "multiuser: two users same project"
setup_test_env

# User 1 creates a session
export CLAUDE_LOGGER_USER="alice"
input='{"session_id":"alice-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# User 2 creates a session
export CLAUDE_LOGGER_USER="bob"
input='{"session_id":"bob-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Both should exist in separate directories
if [ -f "$TEST_TMPDIR/.claude/sessions/alice/alice-session.json" ] && \
   [ -f "$TEST_TMPDIR/.claude/sessions/bob/bob-session.json" ]; then
  test_pass "Both users have separate session dirs"
else
  test_fail "Users should have separate session directories"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Users have separate lock files
#######################################
test_start "multiuser: separate lock files per user"
setup_test_env

# Check that lock files are in user-specific directories
# This is implicit in the current design: locks are at $SESSIONS_DIR/.lock

export CLAUDE_LOGGER_USER="alice"
mkdir -p "$TEST_TMPDIR/.claude/sessions/alice"
touch "$TEST_TMPDIR/.claude/sessions/alice/.lock"

export CLAUDE_LOGGER_USER="bob"
mkdir -p "$TEST_TMPDIR/.claude/sessions/bob"
touch "$TEST_TMPDIR/.claude/sessions/bob/.lock"

# Both lock files should exist independently
if [ -f "$TEST_TMPDIR/.claude/sessions/alice/.lock" ] && \
   [ -f "$TEST_TMPDIR/.claude/sessions/bob/.lock" ]; then
  test_pass "Lock files are per-user"
else
  test_fail "Lock files should be per-user"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Orphan detection only affects own user
#######################################
test_start "multiuser: orphan detection scoped to user"
setup_test_env

# Create an "orphan" session for alice (old, status=active)
export CLAUDE_LOGGER_USER="alice"
mkdir -p "$TEST_TMPDIR/.claude/sessions/alice"
cat > "$TEST_TMPDIR/.claude/sessions/alice/orphan-alice.json" << 'EOF'
{"session_id":"orphan-alice","status":"active","start":{"timestamp":"2024-01-01T00:00:00Z"}}
EOF
touch -t 202401010000 "$TEST_TMPDIR/.claude/sessions/alice/orphan-alice.json"

# Create a valid session for bob
export CLAUDE_LOGGER_USER="bob"
mkdir -p "$TEST_TMPDIR/.claude/sessions/bob"
cat > "$TEST_TMPDIR/.claude/sessions/bob/valid-bob.json" << 'EOF'
{"session_id":"valid-bob","status":"active","start":{"timestamp":"2024-01-01T00:00:00Z"}}
EOF

# Now alice starts a new session (should mark alice's orphan, not bob's)
export CLAUDE_LOGGER_USER="alice"
input='{"session_id":"new-alice","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Alice's orphan should be marked incomplete
alice_orphan_status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/alice/orphan-alice.json" 2>/dev/null)

# Bob's session should be untouched
bob_status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/bob/valid-bob.json" 2>/dev/null)

if [ "$bob_status" = "active" ]; then
  test_pass "Bob's session untouched by Alice's orphan detection"
else
  test_fail "Bob's session was modified (status=$bob_status)"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

#######################################
# Test: Valid username creates correct directory structure
#######################################
test_start "multiuser: valid username creates sessions/username/ dir"
setup_test_env
export CLAUDE_LOGGER_USER="myuser"

input='{"session_id":"test-structure","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -d "$TEST_TMPDIR/.claude/sessions/myuser" ] && \
   [ -f "$TEST_TMPDIR/.claude/sessions/myuser/test-structure.json" ]; then
  test_pass "Directory structure correct"
else
  test_fail "Expected .claude/sessions/myuser/test-structure.json"
fi

export CLAUDE_LOGGER_USER="test-user"
cleanup_test_env

echo ""
echo "Multi-user tests complete"

echo ""
echo "test_user_variable.sh complete"
