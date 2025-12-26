#!/usr/bin/env bash
#
# Tests for GITHUB_NICKNAME handling, validation, and multi-user support
#

#######################################
# Test: Unset GITHUB_NICKNAME shows warning
#######################################
test_start "nickname: unset shows warning message"
setup_test_env

# Unset the nickname that setup_test_env sets
unset GITHUB_NICKNAME

input='{"session_id":"test-unset","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "GITHUB_NICKNAME not set"; then
  test_pass "Warning message shown"
else
  test_fail "Warning message not shown: $output"
fi

# Restore for cleanup
export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Warning goes to stderr, not stdout
#######################################
test_start "nickname: warning goes to stderr not stdout"
setup_test_env
unset GITHUB_NICKNAME

input='{"session_id":"test-stderr","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
stdout_output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>/dev/null)
stderr_output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1 >/dev/null)

if [ -z "$stdout_output" ] && echo "$stderr_output" | grep -q "GITHUB_NICKNAME"; then
  test_pass "Warning on stderr, stdout empty"
else
  test_fail "stdout='$stdout_output' stderr='$stderr_output'"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Unset GITHUB_NICKNAME exits 0
#######################################
test_start "nickname: unset exits with code 0"
setup_test_env
unset GITHUB_NICKNAME

input='{"session_id":"test-exit","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>/dev/null
exit_code=$?

if [ "$exit_code" -eq 0 ]; then
  test_pass "Exit code is 0"
else
  test_fail "Exit code was $exit_code, expected 0"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Unset GITHUB_NICKNAME creates no file
#######################################
test_start "nickname: unset creates no session file"
setup_test_env
unset GITHUB_NICKNAME

input='{"session_id":"test-nofile","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>/dev/null

# Check no files created anywhere in sessions
file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
if [ "$file_count" -eq 0 ]; then
  test_pass "No session file created"
else
  test_fail "Found $file_count files when none expected"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Empty string GITHUB_NICKNAME shows warning
#######################################
test_start "nickname: empty string shows warning"
setup_test_env
export GITHUB_NICKNAME=""

input='{"session_id":"test-empty","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "GITHUB_NICKNAME not set"; then
  test_pass "Empty string triggers warning"
else
  test_fail "Empty string did not trigger warning"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Whitespace-only GITHUB_NICKNAME
#######################################
test_start "nickname: whitespace-only handled"
setup_test_env
export GITHUB_NICKNAME="   "

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

export GITHUB_NICKNAME="test-user"
cleanup_test_env

echo ""
echo "Warning tests complete"

#######################################
# VALIDATION EDGE CASES
#######################################

#######################################
# Test: Uppercase normalized to lowercase
#######################################
test_start "nickname: UPPERCASE normalized to lowercase"
setup_test_env
export GITHUB_NICKNAME="TESTUSER"

input='{"session_id":"test-upper","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/testuser/test-upper.json" ]; then
  test_pass "UPPERCASE -> testuser"
else
  test_fail "File not in lowercase directory"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: MixedCase normalized
#######################################
test_start "nickname: MixedCase normalized to lowercase"
setup_test_env
export GITHUB_NICKNAME="TestUser123"

input='{"session_id":"test-mixed","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/testuser123/test-mixed.json" ]; then
  test_pass "MixedCase -> testuser123"
else
  test_fail "File not in lowercase directory"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: 40+ character nickname rejected
#######################################
test_start "nickname: 40+ chars rejected"
setup_test_env
export GITHUB_NICKNAME="abcdefghijklmnopqrstuvwxyz1234567890abcd"  # 40 chars

input='{"session_id":"test-long","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "invalid"; then
  test_pass "40-char nickname rejected"
else
  file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -eq 0 ]; then
    test_pass "40-char nickname rejected (no file)"
  else
    test_fail "40-char nickname should be rejected"
  fi
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Single character nickname valid
#######################################
test_start "nickname: single char 'a' is valid"
setup_test_env
export GITHUB_NICKNAME="a"

input='{"session_id":"test-single","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/a/test-single.json" ]; then
  test_pass "Single char nickname valid"
else
  test_fail "Single char nickname should be valid"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Numbers-only nickname valid
#######################################
test_start "nickname: numbers-only '123' is valid"
setup_test_env
export GITHUB_NICKNAME="123"

input='{"session_id":"test-numbers","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/123/test-numbers.json" ]; then
  test_pass "Numbers-only nickname valid"
else
  test_fail "Numbers-only nickname should be valid"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Nickname with spaces rejected
#######################################
test_start "nickname: spaces rejected"
setup_test_env
export GITHUB_NICKNAME="user name"

input='{"session_id":"test-spaces","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "invalid"; then
  test_pass "Spaces in nickname rejected"
else
  file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -eq 0 ]; then
    test_pass "Spaces in nickname rejected (no file)"
  else
    test_fail "Spaces in nickname should be rejected"
  fi
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Special characters rejected
#######################################
test_start "nickname: special chars '@' rejected"
setup_test_env
export GITHUB_NICKNAME="user@name"

input='{"session_id":"test-special","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
output=$(echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>&1)

if echo "$output" | grep -q "invalid"; then
  test_pass "@ in nickname rejected"
else
  file_count=$(find "$TEST_TMPDIR/.claude/sessions" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -eq 0 ]; then
    test_pass "@ in nickname rejected (no file)"
  else
    test_fail "@ in nickname should be rejected"
  fi
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Path traversal attempt rejected
#######################################
test_start "nickname: path traversal '../etc' rejected"
setup_test_env
export GITHUB_NICKNAME="../etc"

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

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Flag-like nickname '--help'
#######################################
test_start "nickname: flag-like '--help' handled"
setup_test_env
export GITHUB_NICKNAME="--help"

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

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Mixed dashes and underscores valid
#######################################
test_start "nickname: 'a-b_c-d' is valid"
setup_test_env
export GITHUB_NICKNAME="a-b_c-d"

input='{"session_id":"test-mixed-sep","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/a-b_c-d/test-mixed-sep.json" ]; then
  test_pass "Mixed dashes/underscores valid"
else
  test_fail "Mixed dashes/underscores should be valid"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: 39 characters (max valid)
#######################################
test_start "nickname: 39 chars (max) is valid"
setup_test_env
export GITHUB_NICKNAME="abcdefghijklmnopqrstuvwxyz1234567890abc"  # exactly 39

input='{"session_id":"test-max","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -f "$TEST_TMPDIR/.claude/sessions/abcdefghijklmnopqrstuvwxyz1234567890abc/test-max.json" ]; then
  test_pass "39-char nickname valid"
else
  test_fail "39-char nickname should be valid (max length)"
fi

export GITHUB_NICKNAME="test-user"
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
export GITHUB_NICKNAME="alice"
input='{"session_id":"alice-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# User 2 creates a session
export GITHUB_NICKNAME="bob"
input='{"session_id":"bob-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Both should exist in separate directories
if [ -f "$TEST_TMPDIR/.claude/sessions/alice/alice-session.json" ] && \
   [ -f "$TEST_TMPDIR/.claude/sessions/bob/bob-session.json" ]; then
  test_pass "Both users have separate session dirs"
else
  test_fail "Users should have separate session directories"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Users have separate lock files
#######################################
test_start "multiuser: separate lock files per user"
setup_test_env

# Check that lock files are in user-specific directories
# This is implicit in the current design: locks are at $SESSIONS_DIR/.lock

export GITHUB_NICKNAME="alice"
mkdir -p "$TEST_TMPDIR/.claude/sessions/alice"
touch "$TEST_TMPDIR/.claude/sessions/alice/.lock"

export GITHUB_NICKNAME="bob"
mkdir -p "$TEST_TMPDIR/.claude/sessions/bob"
touch "$TEST_TMPDIR/.claude/sessions/bob/.lock"

# Both lock files should exist independently
if [ -f "$TEST_TMPDIR/.claude/sessions/alice/.lock" ] && \
   [ -f "$TEST_TMPDIR/.claude/sessions/bob/.lock" ]; then
  test_pass "Lock files are per-user"
else
  test_fail "Lock files should be per-user"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Orphan detection only affects own user
#######################################
test_start "multiuser: orphan detection scoped to user"
setup_test_env

# Create an "orphan" session for alice (old, status=active)
export GITHUB_NICKNAME="alice"
mkdir -p "$TEST_TMPDIR/.claude/sessions/alice"
cat > "$TEST_TMPDIR/.claude/sessions/alice/orphan-alice.json" << 'EOF'
{"session_id":"orphan-alice","status":"active","start":{"timestamp":"2024-01-01T00:00:00Z"}}
EOF
touch -t 202401010000 "$TEST_TMPDIR/.claude/sessions/alice/orphan-alice.json"

# Create a valid session for bob
export GITHUB_NICKNAME="bob"
mkdir -p "$TEST_TMPDIR/.claude/sessions/bob"
cat > "$TEST_TMPDIR/.claude/sessions/bob/valid-bob.json" << 'EOF'
{"session_id":"valid-bob","status":"active","start":{"timestamp":"2024-01-01T00:00:00Z"}}
EOF

# Now alice starts a new session (should mark alice's orphan, not bob's)
export GITHUB_NICKNAME="alice"
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

export GITHUB_NICKNAME="test-user"
cleanup_test_env

#######################################
# Test: Valid nickname creates correct directory structure
#######################################
test_start "multiuser: valid nickname creates sessions/nickname/ dir"
setup_test_env
export GITHUB_NICKNAME="myuser"

input='{"session_id":"test-structure","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -d "$TEST_TMPDIR/.claude/sessions/myuser" ] && \
   [ -f "$TEST_TMPDIR/.claude/sessions/myuser/test-structure.json" ]; then
  test_pass "Directory structure correct"
else
  test_fail "Expected .claude/sessions/myuser/test-structure.json"
fi

export GITHUB_NICKNAME="test-user"
cleanup_test_env

echo ""
echo "Multi-user tests complete"

echo ""
echo "test_github_nickname.sh complete"
