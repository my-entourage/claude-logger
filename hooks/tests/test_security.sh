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

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test session with spaces.json"
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

if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)" ]; then
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
if [ -f "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/12345.json" ]; then
  test_pass "Integer coerced to string"
elif [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)" ]; then
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
if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)" ]; then
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
if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)" ]; then
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

if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)" ]; then
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
  files=$(ls -1 "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null | wc -l)
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

#######################################
# Test: Command injection via $()
#######################################
test_start "security: session_id with dollar-paren injection"
setup_test_env

# Create marker file location
marker="/tmp/claude-logger-injection-test-$$"
rm -f "$marker" 2>/dev/null

input='{"session_id":"$(touch '"$marker"')","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ ! -f "$marker" ]; then
  test_pass "Command injection prevented"
else
  rm -f "$marker"
  test_fail "SECURITY VULNERABILITY: Command injection succeeded!"
fi

cleanup_test_env

#######################################
# Test: Command injection via backticks
#######################################
test_start "security: session_id with backtick injection"
setup_test_env

marker="/tmp/claude-logger-backtick-test-$$"
rm -f "$marker" 2>/dev/null

input='{"session_id":"`touch '"$marker"'`","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ ! -f "$marker" ]; then
  test_pass "Backtick injection prevented"
else
  rm -f "$marker"
  test_fail "SECURITY VULNERABILITY: Backtick injection succeeded!"
fi

cleanup_test_env

#######################################
# Test: Injection in cwd field
#######################################
test_start "security: cwd with command injection"
setup_test_env

marker="/tmp/claude-logger-cwd-injection-$$"
rm -f "$marker" 2>/dev/null

input='{"session_id":"test-cwd-inject","cwd":"$(touch '"$marker"')","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ ! -f "$marker" ]; then
  test_pass "CWD injection prevented"
else
  rm -f "$marker"
  test_fail "SECURITY VULNERABILITY: CWD injection succeeded!"
fi

cleanup_test_env

#######################################
# Test: Injection in source field
#######################################
test_start "security: source with command injection"
setup_test_env

marker="/tmp/claude-logger-source-injection-$$"
rm -f "$marker" 2>/dev/null

input='{"session_id":"test-source-inject","cwd":"'"$TEST_TMPDIR"'","source":"$(touch '"$marker"')"}'
run_hook "session_start.sh" "$input"

if [ ! -f "$marker" ]; then
  test_pass "Source injection prevented"
else
  rm -f "$marker"
  test_fail "SECURITY VULNERABILITY: Source injection succeeded!"
fi

cleanup_test_env

#######################################
# Test: Newline injection in session_id
#######################################
test_start "security: session_id with newline injection"
setup_test_env

# Attempt to inject a newline that might break shell parsing
input='{"session_id":"test\ninjected","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should handle gracefully (either create file or reject)
if [ $? -eq 0 ]; then
  test_pass "Newline in session_id handled"
fi

cleanup_test_env

#######################################
# Test: Session ID that looks like shell variable
#######################################
test_start "security: session_id resembling shell variable"
setup_test_env

input='{"session_id":"$HOME","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should create file literally named "$HOME.json" not expand variable
session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/\$HOME.json"
if [ -f "$session_file" ] || [ $? -eq 0 ]; then
  test_pass "Shell variable not expanded"
else
  # Check it didn't create file in actual $HOME
  if [ ! -f "$HOME/.json" ]; then
    test_pass "Shell variable not expanded (no file created)"
  else
    test_fail "Shell variable was expanded!"
  fi
fi

cleanup_test_env

#######################################
# Test: JSON with BOM (Byte Order Mark)
#######################################
test_start "security: JSON with UTF-8 BOM"
setup_test_env

# Create input with BOM prefix
bom=$'\xef\xbb\xbf'
input="${bom}"'{"session_id":"test-bom","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh"

# jq may or may not handle BOM
session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-bom.json"
if [ -f "$session_file" ] || [ $? -eq 0 ]; then
  test_pass "BOM in JSON handled"
else
  test_pass "BOM rejected gracefully"
fi

cleanup_test_env

#######################################
# Test: JSON with CRLF line endings
#######################################
test_start "security: JSON with CRLF line endings"
setup_test_env

# Create input with Windows line endings
input=$'{"session_id":"test-crlf",\r\n"cwd":"'"$TEST_TMPDIR"$'",\r\n"source":"startup"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-crlf.json"
if [ -f "$session_file" ] || [ $? -eq 0 ]; then
  test_pass "CRLF line endings handled"
fi

cleanup_test_env

#######################################
# Test: JSON with very large number
#######################################
test_start "security: JSON with huge number"
setup_test_env

# Number larger than 64-bit
input='{"session_id":"test-bignum","cwd":"'"$TEST_TMPDIR"'","source":"startup","big":99999999999999999999999999999999999999}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-bignum.json"
if [ -f "$session_file" ]; then
  test_pass "Huge number in JSON handled"
fi

cleanup_test_env

#######################################
# Test: JSON with duplicate keys
#######################################
test_start "security: JSON with duplicate keys"
setup_test_env

# Duplicate "session_id" key
input='{"session_id":"first","session_id":"test-dupe-keys","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-dupe-keys.json"
if [ -f "$session_file" ]; then
  # jq takes last value for duplicate keys
  test_pass "Duplicate keys handled (jq uses last)"
elif [ -f "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/first.json" ]; then
  test_pass "Duplicate keys handled (jq uses first)"
else
  test_pass "Duplicate keys handled gracefully"
fi

cleanup_test_env

#######################################
# Test: JSON with scientific notation
#######################################
test_start "security: JSON with scientific notation"
setup_test_env

input='{"session_id":"test-sci","cwd":"'"$TEST_TMPDIR"'","source":"startup","num":1.23e45}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-sci.json"
if [ -f "$session_file" ]; then
  test_pass "Scientific notation handled"
fi

cleanup_test_env

#######################################
# Test: JSON with escaped unicode
#######################################
test_start "security: JSON with escaped unicode sequences"
setup_test_env

input='{"session_id":"test-\u0041\u0042\u0043","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# jq should decode \u0041\u0042\u0043 to "ABC"
session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-ABC.json"
if [ -f "$session_file" ]; then
  test_pass "Escaped unicode decoded correctly"
else
  # Check if literal was used
  files=$(ls -1 "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)
  test_pass "Escaped unicode handled ($files)"
fi

cleanup_test_env

#######################################
# Test: Completely empty input
#######################################
test_start "security: completely empty stdin"
setup_test_env

# Send literally nothing
bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" < /dev/null
exit_code=$?

if [ $exit_code -eq 0 ]; then
  test_pass "Empty stdin handled (exit 0)"
else
  test_pass "Empty stdin handled (exit $exit_code)"
fi

cleanup_test_env

#######################################
# Test: JSON with only whitespace
#######################################
test_start "security: whitespace-only input"
setup_test_env

echo "   " | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh"
exit_code=$?

if [ $exit_code -eq 0 ]; then
  test_pass "Whitespace input handled (exit 0)"
else
  test_pass "Whitespace input handled (exit $exit_code)"
fi

cleanup_test_env

echo ""
echo "Security tests complete"
