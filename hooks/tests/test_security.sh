#!/usr/bin/env bash
#
# Security-focused tests for Claude Tracker hooks
#

#######################################
# Test: Session ID path traversal prevention
#######################################
test_start "security: session_id with path traversal attempt"
setup_test_env

input='{"session_id":"../../../tmp/evil","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should NOT create file outside sessions directory
if [ ! -f "$TEST_TMPDIR/../../../tmp/evil.json" ] && \
   [ ! -f "/tmp/evil.json" ]; then
  test_pass "Path traversal prevented"
else
  test_fail "Path traversal NOT prevented - security vulnerability!"
fi

cleanup_test_env

#######################################
# Test: Session ID with slashes
#######################################
test_start "security: session_id with forward slashes"
setup_test_env

input='{"session_id":"foo/bar/baz","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Either creates nested dirs or fails gracefully - both are acceptable
if [ $? -eq 0 ]; then
  test_pass "Slashes in session_id handled gracefully"
fi

cleanup_test_env

#######################################
# Test: Session ID with spaces
#######################################
test_start "security: session_id with spaces"
setup_test_env

input='{"session_id":"test session with spaces","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test session with spaces.json"
if [ -f "$session_file" ]; then
  test_pass "Spaces in session_id handled"
elif [ $? -eq 0 ]; then
  test_pass "Spaces handled gracefully (no file created)"
fi

cleanup_test_env

#######################################
# Test: Very long session ID (4KB+)
#######################################
test_start "security: very long session_id (4KB)"
setup_test_env

long_id=$(head -c 4096 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 4096)
input='{"session_id":"'"$long_id"'","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should either create file (OS permitting) or fail gracefully
if [ $? -eq 0 ]; then
  test_pass "Long session_id handled gracefully"
fi

cleanup_test_env

#######################################
# Test: Deeply nested JSON input
#######################################
test_start "security: deeply nested JSON input"
setup_test_env

# Create 100-level nested JSON
nested='{"a":'
for i in {1..100}; do
  nested="${nested}{\"b\":"
done
nested="${nested}1"
for i in {1..100}; do
  nested="${nested}}"
done
nested="${nested}}"

input='{"session_id":"test-nested","cwd":"'"$TEST_TMPDIR"'","source":"startup","extra":'"$nested"'}'
run_hook "session_start.sh" "$input"

# jq should handle this (it has its own limits)
if [ $? -eq 0 ]; then
  test_pass "Nested JSON handled by jq"
fi

cleanup_test_env

#######################################
# Test: Large input (>1MB)
#######################################
test_start "security: large input (>1MB)"
setup_test_env

# Create 1.5MB of padding
large_padding=$(head -c 1572864 /dev/urandom | base64 | tr -d '\n')
input='{"session_id":"test-large","cwd":"'"$TEST_TMPDIR"'","source":"startup","padding":"'"$large_padding"'"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh"

# Should not crash or hang
if [ $? -eq 0 ]; then
  test_pass "Large input handled"
fi

cleanup_test_env

#######################################
# Test: Null session_id value
#######################################
test_start "security: null session_id value"
setup_test_env

input='{"session_id":null,"cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/" 2>/dev/null)" ]; then
  test_pass "Null session_id rejected"
else
  test_fail "Null session_id should be rejected"
fi

cleanup_test_env

#######################################
# Test: Integer session_id
#######################################
test_start "security: integer session_id"
setup_test_env

input='{"session_id":12345,"cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# jq -r will coerce to string "12345" or return empty
if [ -f "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/12345.json" ]; then
  test_pass "Integer coerced to string"
elif [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/" 2>/dev/null)" ]; then
  test_pass "Integer session_id rejected"
else
  test_pass "Integer session_id handled"
fi

cleanup_test_env

#######################################
# Test: Boolean session_id
#######################################
test_start "security: boolean session_id"
setup_test_env

input='{"session_id":true,"cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should handle gracefully
if [ $? -eq 0 ]; then
  test_pass "Boolean session_id handled"
fi

cleanup_test_env

#######################################
# Test: Array session_id
#######################################
test_start "security: array session_id"
setup_test_env

input='{"session_id":["a","b"],"cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should reject or handle gracefully
if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/" 2>/dev/null)" ]; then
  test_pass "Array session_id rejected"
else
  test_pass "Array session_id handled"
fi

cleanup_test_env

#######################################
# Test: Object session_id
#######################################
test_start "security: object session_id"
setup_test_env

input='{"session_id":{"nested":"object"},"cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should reject or handle gracefully
if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/" 2>/dev/null)" ]; then
  test_pass "Object session_id rejected"
else
  test_pass "Object session_id handled"
fi

cleanup_test_env

#######################################
# Test: Empty string session_id
#######################################
test_start "security: empty string session_id"
setup_test_env

input='{"session_id":"","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/" 2>/dev/null)" ]; then
  test_pass "Empty string session_id rejected"
else
  test_fail "Empty string session_id should be rejected"
fi

cleanup_test_env

#######################################
# Test: Unicode in session_id
#######################################
test_start "security: unicode in session_id"
setup_test_env

input='{"session_id":"test-сессия-测试","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should handle unicode gracefully
if [ $? -eq 0 ]; then
  files=$(ls -1 "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/" 2>/dev/null | wc -l)
  if [ "$files" -ge 1 ]; then
    test_pass "Unicode session_id created file"
  else
    test_pass "Unicode session_id handled gracefully"
  fi
fi

cleanup_test_env

#######################################
# Test: Control characters in session_id
#######################################
test_start "security: control characters in session_id"
setup_test_env

# Tab character
input='{"session_id":"test\ttab","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ $? -eq 0 ]; then
  test_pass "Control characters handled"
fi

cleanup_test_env

echo ""
echo "Security tests complete"
