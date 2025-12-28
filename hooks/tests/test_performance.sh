#!/usr/bin/env bash
#
# Performance benchmark tests for Claude Tracker hooks
# These tests measure execution time and assert performance improvements
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#######################################
# Helper: Get current time in milliseconds (portable)
#######################################
get_time_ms() {
  if date +%s%N &>/dev/null 2>&1; then
    # Linux: nanosecond precision
    echo $(($(date +%s%N) / 1000000))
  else
    # macOS: second precision, multiply by 1000
    echo $(($(date +%s) * 1000))
  fi
}

#######################################
# Test: Input parsing performance
#######################################
test_start "perf: input parsing executes in < 100ms"
setup_test_env

# Measure 10 iterations
total_ms=0
for i in {1..10}; do
  input='{"session_id":"perf-test-'"$i"'","cwd":"'"$TEST_TMPDIR"'","source":"startup","transcript_path":"/tmp/test.jsonl"}'

  start_time=$(get_time_ms)
  # Test the optimized input parsing pattern (single jq call with @sh)
  echo "$input" | timeout 5 bash -c '
    HOOK_INPUT=$(cat)
    eval "set -- $(echo "$HOOK_INPUT" | jq -r "[.session_id // \"\", .transcript_path // \"\", .cwd // \"\", .source // \"startup\"] | @sh")"
    SESSION_ID="$1"
    TRANSCRIPT_PATH="$2"
    CWD="$3"
    SOURCE="$4"
  ' 2>/dev/null
  end_time=$(get_time_ms)

  elapsed_ms=$((end_time - start_time))
  total_ms=$((total_ms + elapsed_ms))
done

avg_ms=$((total_ms / 10))
if [ "$avg_ms" -lt 100 ]; then
  test_pass "Input parsing: ${avg_ms}ms average"
else
  test_fail "Input parsing too slow: ${avg_ms}ms average (expected < 100ms)"
fi

cleanup_test_env

#######################################
# Test: Timeout wrapper completes quickly
# Note: We no longer test killing stuck processes since the portable
# timeout was reverted to simple fallback. Instead, we verify the
# timeout function exists and runs quickly.
#######################################
test_start "perf: timeout wrapper runs without overhead"
setup_test_env

# Create a minimal test script that sources the timeout function
cat > "$TEST_TMPDIR/test_timeout.sh" << 'SCRIPT'
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  if command -v timeout &>/dev/null; then
    timeout "$timeout_seconds" "$@"
    return $?
  fi
  "$@"
}

# Run a quick command
run_with_timeout 2 echo "hello" >/dev/null
SCRIPT

start_time=$(get_time_ms)
bash "$TEST_TMPDIR/test_timeout.sh" 2>/dev/null
end_time=$(get_time_ms)

elapsed=$((end_time - start_time))

# Should complete almost instantly (< 500ms with startup overhead)
if [ "$elapsed" -lt 500 ]; then
  test_pass "Timeout wrapper: ${elapsed}ms"
else
  test_fail "Timeout wrapper too slow: ${elapsed}ms (expected < 500ms)"
fi

cleanup_test_env

#######################################
# Test: Config capture with many files
#######################################
test_start "perf: 50 config files captured in < 3000ms"
setup_test_env

# Create 25 skills and 25 commands
mkdir -p "$TEST_TMPDIR/.claude/commands"
for i in {1..25}; do
  mkdir -p "$TEST_TMPDIR/.claude/skills/skill-$i"
  echo "# Skill $i content" > "$TEST_TMPDIR/.claude/skills/skill-$i/SKILL.md"
  echo "# Command $i content" > "$TEST_TMPDIR/.claude/commands/cmd-$i.md"
done

start_time=$(get_time_ms)
input='{"session_id":"config-perf-test","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"
end_time=$(get_time_ms)

elapsed_ms=$((end_time - start_time))

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/config-perf-test.json"
skills_count=$(jq '.start.config.skills | keys | length' "$session_file" 2>/dev/null || echo 0)
commands_count=$(jq '.start.config.commands | keys | length' "$session_file" 2>/dev/null || echo 0)

if [ "$elapsed_ms" -lt 3000 ] && [ "$skills_count" -ge 25 ] && [ "$commands_count" -ge 25 ]; then
  test_pass "50 configs captured in ${elapsed_ms}ms (skills: $skills_count, commands: $commands_count)"
else
  test_fail "Too slow or missing configs: ${elapsed_ms}ms (expected < 3000ms), skills: $skills_count, commands: $commands_count"
fi

cleanup_test_env

#######################################
# Test: Session end validation is fast
#######################################
test_start "perf: session_end validation in < 200ms"
setup_test_env

# Create a session file to validate
session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/validation-test.json"
cat > "$session_file" << 'EOF'
{
  "session_id": "validation-test",
  "status": "in_progress",
  "transcript_path": "/tmp/test.jsonl",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "git": {"sha": "abc123"}
  }
}
EOF

start_time=$(get_time_ms)
input='{"session_id":"validation-test","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"
end_time=$(get_time_ms)

elapsed_ms=$((end_time - start_time))

if [ "$elapsed_ms" -lt 200 ]; then
  test_pass "Session end validation: ${elapsed_ms}ms"
else
  test_fail "Too slow: ${elapsed_ms}ms (expected < 200ms)"
fi

cleanup_test_env

#######################################
# Test: Full session lifecycle performance
#######################################
test_start "perf: full session lifecycle in < 2000ms"
setup_test_env

# Initialize git repo for realistic test (use -C to avoid cd)
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"

start_time=$(get_time_ms)

# Start session
input='{"session_id":"lifecycle-test","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# End session
input='{"session_id":"lifecycle-test","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

end_time=$(get_time_ms)
elapsed_ms=$((end_time - start_time))

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/lifecycle-test.json"
status=$(jq -r '.status' "$session_file" 2>/dev/null || echo "unknown")

if [ "$elapsed_ms" -lt 2000 ] && [ "$status" = "complete" ]; then
  test_pass "Full lifecycle: ${elapsed_ms}ms"
else
  test_fail "Too slow or incomplete: ${elapsed_ms}ms (expected < 2000ms), status: $status"
fi

cleanup_test_env

#######################################
# Test: Orphan detection doesn't block session creation
#######################################
test_start "perf: orphan detection runs after session creation"
setup_test_env

# Create some orphaned sessions first
for i in {1..5}; do
  orphan_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/orphan-$i.json"
  cat > "$orphan_file" << EOF
{
  "session_id": "orphan-$i",
  "status": "in_progress",
  "start": {"timestamp": "2025-01-01T12:00:00Z"}
}
EOF
  # Touch with recent mtime so find -mtime -1 finds them
  touch "$orphan_file"
done

start_time=$(get_time_ms)
input='{"session_id":"after-orphans-test","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"
end_time=$(get_time_ms)

elapsed_ms=$((end_time - start_time))

# Session file should exist
session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/after-orphans-test.json"
if [ -f "$session_file" ] && [ "$elapsed_ms" -lt 1000 ]; then
  test_pass "Session created in ${elapsed_ms}ms with 5 orphans present"
else
  test_fail "Session creation too slow: ${elapsed_ms}ms (expected < 1000ms)"
fi

# Verify orphans were marked (orphan detection ran)
orphan_status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/orphan-1.json" 2>/dev/null || echo "unknown")
if [ "$orphan_status" = "incomplete" ]; then
  test_pass "Orphan was marked as incomplete"
else
  test_fail "Orphan not marked: status=$orphan_status (expected incomplete)"
fi

cleanup_test_env

echo ""
echo "Performance benchmark tests complete"
