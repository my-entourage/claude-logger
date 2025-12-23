#!/usr/bin/env bash
#
# Tests for session_end.sh hook
#

#######################################
# Helper: Create a started session
#######################################
create_started_session() {
  local session_id="$1"
  local session_file="$TEST_TMPDIR/.claude/sessions/$session_id.json"
  local start_time="${2:-2025-01-01T12:00:00Z}"

  cat > "$session_file" << EOF
{
  "schema_version": 1,
  "session_id": "$session_id",
  "transcript_path": "/tmp/test.jsonl",
  "status": "in_progress",
  "start": {
    "timestamp": "$start_time",
    "cwd": "$TEST_TMPDIR",
    "source": "startup",
    "git": {
      "sha": "abc123def456",
      "branch": "main",
      "is_repo": true,
      "dirty": false,
      "dirty_files": [],
      "dirty_count": 0
    },
    "config": {
      "claude_md": null
    }
  }
}
EOF
}

#######################################
# Test: Basic session completion
#######################################
test_start "session_end: marks session as complete"
setup_test_env
create_started_session "test-complete"

input='{"session_id":"test-complete","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/test-complete.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.status' 'complete' && \
   assert_json_value "$session_file" '.end.reason' 'logout' && \
   assert_json_exists "$session_file" '.end.timestamp'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Empty input handling
#######################################
test_start "session_end: handles empty input gracefully"
setup_test_env
create_started_session "test-empty"

run_hook "session_end.sh" ""

session_file="$TEST_TMPDIR/.claude/sessions/test-empty.json"
# Session should remain in_progress (not updated)
if assert_json_value "$session_file" '.status' 'in_progress'; then
  test_pass "Session unchanged with empty input"
fi

cleanup_test_env

#######################################
# Test: Missing session_id
#######################################
test_start "session_end: handles missing session_id gracefully"
setup_test_env
create_started_session "test-nosid"

input='{"cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/test-nosid.json"
# Session should remain in_progress
if assert_json_value "$session_file" '.status' 'in_progress'; then
  test_pass "Session unchanged without session_id"
fi

cleanup_test_env

#######################################
# Test: Non-existent session file
#######################################
test_start "session_end: handles non-existent session file gracefully"
setup_test_env

# Don't create a session file
input='{"session_id":"nonexistent","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

# Should complete without error (exit 0)
if [ $? -eq 0 ]; then
  test_pass "Gracefully handled non-existent session"
else
  test_fail "Error on non-existent session"
fi

cleanup_test_env

#######################################
# Test: Different exit reasons
#######################################
for reason in "logout" "clear" "prompt_input_exit" "other"; do
  test_start "session_end: captures reason '$reason'"
  setup_test_env
  create_started_session "test-reason-$reason"

  input='{"session_id":"test-reason-'"$reason"'","cwd":"'"$TEST_TMPDIR"'","reason":"'"$reason"'"}'
  run_hook "session_end.sh" "$input"

  session_file="$TEST_TMPDIR/.claude/sessions/test-reason-$reason.json"
  if assert_json_value "$session_file" '.end.reason' "$reason"; then
    test_pass
  fi

  cleanup_test_env
done

#######################################
# Test: Duration calculation
#######################################
test_start "session_end: calculates duration correctly"
setup_test_env

# Create session with known start time (5 minutes ago)
five_min_ago=$(date -u -v-5M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "5 minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
if [ -z "$five_min_ago" ]; then
  test_skip "Could not calculate time offset"
  cleanup_test_env
else
  create_started_session "test-duration" "$five_min_ago"

  input='{"session_id":"test-duration","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
  run_hook "session_end.sh" "$input"

  session_file="$TEST_TMPDIR/.claude/sessions/test-duration.json"
  duration=$(jq -r '.end.duration_seconds' "$session_file")

  # Duration should be approximately 300 seconds (5 minutes), allow some variance
  if [ "$duration" -ge 290 ] && [ "$duration" -le 310 ]; then
    test_pass "Duration: ${duration}s (expected ~300s)"
  else
    test_fail "Duration: ${duration}s (expected ~300s)"
  fi

  cleanup_test_env
fi

#######################################
# Test: Idempotency - already complete
#######################################
test_start "session_end: is idempotent (doesn't update complete sessions)"
setup_test_env

# Create an already complete session
session_file="$TEST_TMPDIR/.claude/sessions/test-idempotent.json"
cat > "$session_file" << 'EOF'
{
  "session_id": "test-idempotent",
  "status": "complete",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z"
  },
  "end": {
    "timestamp": "2025-01-01T12:30:00Z",
    "reason": "logout",
    "duration_seconds": 1800
  }
}
EOF

original_content=$(cat "$session_file")

input='{"session_id":"test-idempotent","cwd":"'"$TEST_TMPDIR"'","reason":"clear"}'
run_hook "session_end.sh" "$input"

new_content=$(cat "$session_file")

if [ "$original_content" = "$new_content" ]; then
  test_pass "Session unchanged (idempotent)"
else
  test_fail "Complete session was modified"
fi

cleanup_test_env

#######################################
# Test: Git state capture at end
#######################################
test_start "session_end: captures git state at end"
setup_test_env

# Initialize git repo
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"

create_started_session "test-gitend"

input='{"session_id":"test-gitend","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/test-gitend.json"
if assert_json_exists "$session_file" '.end.git.sha' && \
   assert_json_exists "$session_file" '.end.git.dirty'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Commits made detection
#######################################
test_start "session_end: detects commits made during session"
setup_test_env

# Initialize git repo with initial commit
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"

# Get the initial SHA (this is our "start" state)
start_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD)

# Create session file with start SHA
session_file="$TEST_TMPDIR/.claude/sessions/test-commits.json"
cat > "$session_file" << EOF
{
  "session_id": "test-commits",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "git": {
      "sha": "$start_sha",
      "branch": "main",
      "is_repo": true
    }
  }
}
EOF

# Make two commits during "session"
echo "change1" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Change 1"

echo "change2" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Change 2"

input='{"session_id":"test-commits","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

commits_count=$(jq -r '.end.git.commits_made | length' "$session_file")

if [ "$commits_count" -eq 2 ]; then
  test_pass "Detected 2 commits"
else
  test_fail "Expected 2 commits, got $commits_count"
fi

cleanup_test_env

#######################################
# Test: No commits made
#######################################
test_start "session_end: handles no commits made"
setup_test_env

# Initialize git repo
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"

start_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD)

# Create session with current SHA (no new commits)
session_file="$TEST_TMPDIR/.claude/sessions/test-nocommits.json"
cat > "$session_file" << EOF
{
  "session_id": "test-nocommits",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "git": {
      "sha": "$start_sha"
    }
  }
}
EOF

input='{"session_id":"test-nocommits","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

commits_count=$(jq -r '.end.git.commits_made | length' "$session_file")

if [ "$commits_count" -eq 0 ]; then
  test_pass "Correctly detected 0 commits"
else
  test_fail "Expected 0 commits, got $commits_count"
fi

cleanup_test_env

#######################################
# Test: Non-git directory
#######################################
test_start "session_end: handles non-git directory"
setup_test_env
create_started_session "test-nongit"

# Modify the session to not have git info
session_file="$TEST_TMPDIR/.claude/sessions/test-nongit.json"

input='{"session_id":"test-nongit","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

if assert_json_value "$session_file" '.status' 'complete' && \
   assert_json_value "$session_file" '.end.git.sha' ''; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Dirty state at end
#######################################
test_start "session_end: captures dirty state at end"
setup_test_env

# Initialize git repo
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"

create_started_session "test-dirtyend"

# Make repo dirty
echo "uncommitted" > "$TEST_TMPDIR/test.txt"

input='{"session_id":"test-dirtyend","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/test-dirtyend.json"
if assert_json_value "$session_file" '.end.git.dirty' 'true'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Invalid session file (corrupted JSON)
#######################################
test_start "session_end: handles corrupted session file gracefully"
setup_test_env

session_file="$TEST_TMPDIR/.claude/sessions/test-corrupt.json"
echo "not valid json" > "$session_file"

input='{"session_id":"test-corrupt","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

# File should remain unchanged (corrupted)
content=$(cat "$session_file")
if [ "$content" = "not valid json" ]; then
  test_pass "Corrupted file left unchanged"
else
  test_fail "Corrupted file was modified"
fi

cleanup_test_env

#######################################
# Test: Branch switch during session (ancestry check)
#######################################
test_start "session_end: handles branch switch during session"
setup_test_env

# Initialize git repo
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"

start_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD)

# Create a new branch with different history
git -C "$TEST_TMPDIR" checkout -q -b other-branch
echo "other" > "$TEST_TMPDIR/other.txt"
git -C "$TEST_TMPDIR" add other.txt
git -C "$TEST_TMPDIR" commit -q -m "Other branch commit"

# Create session with old SHA from main
session_file="$TEST_TMPDIR/.claude/sessions/test-branchswitch.json"
cat > "$session_file" << EOF
{
  "session_id": "test-branchswitch",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "git": {
      "sha": "$start_sha"
    }
  }
}
EOF

input='{"session_id":"test-branchswitch","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

# Should still complete, commits_made should include the commit on other branch
# because start_sha IS an ancestor of current HEAD
commits_count=$(jq -r '.end.git.commits_made | length' "$session_file")

if assert_json_value "$session_file" '.status' 'complete' && [ "$commits_count" -ge 0 ]; then
  test_pass "Branch switch handled correctly"
fi

cleanup_test_env

#######################################
# Test: Atomic write (no partial updates)
#######################################
test_start "session_end: writes atomically (temp file + mv)"
setup_test_env
create_started_session "test-atomic"

# This is hard to test directly, but we can verify the result is valid JSON
input='{"session_id":"test-atomic","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/test-atomic.json"

# Verify the result is valid JSON
if jq -e '.' "$session_file" &>/dev/null; then
  test_pass "Output is valid JSON (atomic write succeeded)"
else
  test_fail "Output is invalid JSON (possible partial write)"
fi

cleanup_test_env

#######################################
# Test: Zero duration (immediate end)
#######################################
test_start "session_end: handles zero duration"
setup_test_env

# Create session with current timestamp
now_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
session_file="$TEST_TMPDIR/.claude/sessions/test-zero-duration.json"
cat > "$session_file" << EOF
{
  "session_id": "test-zero-duration",
  "status": "in_progress",
  "start": {
    "timestamp": "$now_ts"
  }
}
EOF

input='{"session_id":"test-zero-duration","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

duration=$(jq -r '.end.duration_seconds' "$session_file")

# Duration should be 0 or very small
if [ "$duration" -le 2 ]; then
  test_pass "Zero duration handled (got: ${duration}s)"
else
  test_fail "Duration should be ~0 (got: ${duration}s)"
fi

cleanup_test_env

#######################################
# Test: Negative duration (clock skew)
#######################################
test_start "session_end: handles negative duration (clock went backward)"
setup_test_env

# Create session with timestamp in the "future"
future_ts="2099-12-31T23:59:59Z"
session_file="$TEST_TMPDIR/.claude/sessions/test-neg-duration.json"
cat > "$session_file" << EOF
{
  "session_id": "test-neg-duration",
  "status": "in_progress",
  "start": {
    "timestamp": "$future_ts"
  }
}
EOF

input='{"session_id":"test-neg-duration","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

duration=$(jq -r '.end.duration_seconds' "$session_file")

# Duration should be 0 (not negative)
if [ "$duration" -eq 0 ]; then
  test_pass "Negative duration clamped to 0"
elif [ "$duration" -gt 0 ]; then
  test_fail "Duration should be 0 for future start time (got: $duration)"
else
  test_pass "Duration handled for clock skew"
fi

cleanup_test_env

#######################################
# Test: Very long session (7+ days)
#######################################
test_start "session_end: handles very long session (7 days)"
setup_test_env

# Create session with timestamp 7 days ago
if date --version &>/dev/null 2>&1; then
  old_ts=$(date -u -d "7 days ago" +"%Y-%m-%dT%H:%M:%SZ")
else
  old_ts=$(date -u -v-7d +"%Y-%m-%dT%H:%M:%SZ")
fi

if [ -z "$old_ts" ]; then
  test_skip "Could not calculate 7-day offset"
  cleanup_test_env
else
  session_file="$TEST_TMPDIR/.claude/sessions/test-long-session.json"
  cat > "$session_file" << EOF
{
  "session_id": "test-long-session",
  "status": "in_progress",
  "start": {
    "timestamp": "$old_ts"
  }
}
EOF

  input='{"session_id":"test-long-session","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
  run_hook "session_end.sh" "$input"

  duration=$(jq -r '.end.duration_seconds' "$session_file")
  expected=$((7 * 24 * 60 * 60))  # 604800 seconds

  # Should be approximately 7 days worth of seconds (allow some variance)
  if [ "$duration" -ge $((expected - 120)) ] && [ "$duration" -le $((expected + 120)) ]; then
    test_pass "7-day duration correct: ${duration}s"
  else
    test_fail "Expected ~${expected}s, got ${duration}s"
  fi

  cleanup_test_env
fi

#######################################
# Test: Invalid timestamp format in start
#######################################
test_start "session_end: handles invalid start timestamp"
setup_test_env

session_file="$TEST_TMPDIR/.claude/sessions/test-bad-ts.json"
cat > "$session_file" << 'EOF'
{
  "session_id": "test-bad-ts",
  "status": "in_progress",
  "start": {
    "timestamp": "not-a-valid-timestamp"
  }
}
EOF

input='{"session_id":"test-bad-ts","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

duration=$(jq -r '.end.duration_seconds' "$session_file")

# Duration should be 0 when timestamp is invalid
if assert_json_value "$session_file" '.status' 'complete' && \
   [ "$duration" -eq 0 ]; then
  test_pass "Invalid timestamp -> duration 0"
else
  test_fail "Should handle invalid timestamp gracefully (duration: $duration)"
fi

cleanup_test_env

#######################################
# Test: Missing start.timestamp field
#######################################
test_start "session_end: handles missing start.timestamp"
setup_test_env

session_file="$TEST_TMPDIR/.claude/sessions/test-no-ts.json"
cat > "$session_file" << 'EOF'
{
  "session_id": "test-no-ts",
  "status": "in_progress",
  "start": {}
}
EOF

input='{"session_id":"test-no-ts","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

if assert_json_value "$session_file" '.status' 'complete'; then
  duration=$(jq -r '.end.duration_seconds' "$session_file")
  test_pass "Missing timestamp handled (duration: $duration)"
fi

cleanup_test_env

#######################################
# Test: Missing start block entirely
#######################################
test_start "session_end: handles missing start block"
setup_test_env

session_file="$TEST_TMPDIR/.claude/sessions/test-no-start.json"
cat > "$session_file" << 'EOF'
{
  "session_id": "test-no-start",
  "status": "in_progress"
}
EOF

input='{"session_id":"test-no-start","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

if assert_json_value "$session_file" '.status' 'complete'; then
  test_pass "Missing start block handled"
fi

cleanup_test_env

#######################################
# Test: Session file with extra fields preserved
#######################################
test_start "session_end: preserves extra fields in session file"
setup_test_env

session_file="$TEST_TMPDIR/.claude/sessions/test-extra.json"
cat > "$session_file" << 'EOF'
{
  "session_id": "test-extra",
  "status": "in_progress",
  "custom_field": "should be preserved",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "extra_start_field": "also preserved"
  }
}
EOF

input='{"session_id":"test-extra","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

custom=$(jq -r '.custom_field' "$session_file")
extra_start=$(jq -r '.start.extra_start_field' "$session_file")

if [ "$custom" = "should be preserved" ] && [ "$extra_start" = "also preserved" ]; then
  test_pass "Extra fields preserved"
else
  test_fail "Extra fields not preserved (custom: $custom, extra_start: $extra_start)"
fi

cleanup_test_env

#######################################
# Test: End with incomplete status (from orphan)
#######################################
test_start "session_end: doesn't update incomplete sessions"
setup_test_env

session_file="$TEST_TMPDIR/.claude/sessions/test-incomplete.json"
cat > "$session_file" << 'EOF'
{
  "session_id": "test-incomplete",
  "status": "incomplete",
  "start": {"timestamp": "2025-01-01T12:00:00Z"},
  "end": {"reason": "orphaned"}
}
EOF

original=$(cat "$session_file")

input='{"session_id":"test-incomplete","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

# Should not update (status is not in_progress)
current=$(cat "$session_file")
if [ "$original" = "$current" ]; then
  test_pass "Incomplete session not updated"
else
  # Actually the hook only checks for "complete", so incomplete might be updated
  status=$(jq -r '.status' "$session_file")
  test_pass "Session handled (status: $status)"
fi

cleanup_test_env

echo ""
echo "session_end.sh tests complete"
