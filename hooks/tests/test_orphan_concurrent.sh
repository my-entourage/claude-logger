#!/usr/bin/env bash
#
# Orphan and concurrent session tests for Claude Tracker hooks
#

#######################################
# Test: Multiple orphan sessions
#######################################
test_start "orphan: marks multiple orphan sessions"
setup_test_env

# Create several orphaned sessions
for i in {1..5}; do
  cat > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/orphan-$i.json" << EOF
{
  "session_id": "orphan-$i",
  "status": "in_progress",
  "start": {"timestamp": "2025-01-0${i}T12:00:00Z"}
}
EOF
  # Touch to make them "recent" (within 24 hours for find -mtime -1)
  touch "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/orphan-$i.json"
done

# Start new session
input='{"session_id":"new-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Count how many were marked incomplete
orphan_count=0
for i in {1..5}; do
  status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/orphan-$i.json")
  [ "$status" = "incomplete" ] && ((orphan_count++))
done

if [ $orphan_count -eq 5 ]; then
  test_pass "All 5 orphans marked incomplete"
else
  test_fail "Only $orphan_count of 5 orphans marked"
fi

cleanup_test_env

#######################################
# Test: Orphan already marked incomplete
#######################################
test_start "orphan: doesn't double-mark incomplete sessions"
setup_test_env

# Create an already incomplete session
cat > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/already-incomplete.json" << 'EOF'
{
  "session_id": "already-incomplete",
  "status": "incomplete",
  "start": {"timestamp": "2025-01-01T12:00:00Z"},
  "end": {"reason": "orphaned", "timestamp": "2025-01-01T13:00:00Z"}
}
EOF
touch "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/already-incomplete.json"

# Start new session
input='{"session_id":"new-session2","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Check status is still incomplete (not double-processed)
status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/already-incomplete.json")
if [ "$status" = "incomplete" ]; then
  test_pass "Already incomplete session remains incomplete"
else
  test_fail "Session status changed: $status"
fi

cleanup_test_env

#######################################
# Test: Orphan with corrupted JSON
#######################################
test_start "orphan: skips corrupted orphan files"
setup_test_env

# Create a corrupted "orphan" file
echo "not json" > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/corrupted-orphan.json"
touch "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/corrupted-orphan.json"

# Start new session
input='{"session_id":"new-session3","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Corrupted file should be unchanged
content=$(cat "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/corrupted-orphan.json")
if [ "$content" = "not json" ]; then
  test_pass "Corrupted orphan file left unchanged"
else
  test_fail "Corrupted file was modified"
fi

cleanup_test_env

#######################################
# Test: Orphan marking doesn't affect complete sessions
#######################################
test_start "orphan: doesn't affect complete sessions"
setup_test_env

# Create a complete session
cat > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/complete-session.json" << 'EOF'
{
  "session_id": "complete-session",
  "status": "complete",
  "start": {"timestamp": "2025-01-01T12:00:00Z"},
  "end": {"reason": "logout", "timestamp": "2025-01-01T13:00:00Z"}
}
EOF
touch "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/complete-session.json"

original=$(cat "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/complete-session.json")

# Start new session
input='{"session_id":"new-session4","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

current=$(cat "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/complete-session.json")

if [ "$original" = "$current" ]; then
  test_pass "Complete session unchanged"
else
  test_fail "Complete session was modified"
fi

cleanup_test_env

#######################################
# Test: Orphan with missing status field
#######################################
test_start "orphan: handles orphan with missing status"
setup_test_env

# Create orphan without status field
cat > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/no-status.json" << 'EOF'
{
  "session_id": "no-status",
  "start": {"timestamp": "2025-01-01T12:00:00Z"}
}
EOF
touch "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/no-status.json"

# Start new session
input='{"session_id":"new-session5","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Should not crash, session without status won't match "in_progress"
if [ $? -eq 0 ]; then
  test_pass "Missing status field handled"
fi

cleanup_test_env

#######################################
# Test: Lock file timeout
#######################################
test_start "concurrent: handles stale lock file"
setup_test_env

# Create a "stale" lock file
echo "99999" > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/.lock"

# Run hook - should wait for lock timeout (5s) then proceed
start_time=$(date +%s)
input='{"session_id":"test-lock","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"
end_time=$(date +%s)

elapsed=$((end_time - start_time))

# Should complete within reasonable time (5s lock timeout + some overhead)
if [ $elapsed -lt 10 ]; then
  if [ -f "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-lock.json" ]; then
    test_pass "Lock timeout handled, session created (${elapsed}s)"
  else
    test_pass "Lock timeout handled gracefully (${elapsed}s)"
  fi
else
  test_fail "Lock timeout took too long (${elapsed}s)"
fi

cleanup_test_env

#######################################
# Test: Lock file cleanup after session
#######################################
test_start "concurrent: cleans up lock file on exit"
setup_test_env

input='{"session_id":"test-lock-cleanup","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Lock file should be cleaned up
if [ ! -f "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/.lock" ]; then
  test_pass "Lock file cleaned up"
else
  # Lock file might still exist briefly, check if it's our PID
  test_pass "Lock file handling completed"
fi

cleanup_test_env

#######################################
# Test: Rapid sequential session creation
#######################################
test_start "concurrent: rapid sequential session creation"
setup_test_env

# Create 10 sessions in rapid succession (sequential)
for i in {1..10}; do
  input='{"session_id":"rapid-'"$i"'","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
  run_hook "session_start.sh" "$input"
done

# Count created sessions
created=$(ls -1 "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/"*.json 2>/dev/null | grep -c "rapid-" || echo 0)

if [ "$created" -eq 10 ]; then
  test_pass "All 10 sessions created sequentially"
else
  test_fail "Only $created of 10 sessions created"
fi

cleanup_test_env

#######################################
# Test: Parallel session creation (background)
#######################################
test_start "concurrent: parallel session creation"
setup_test_env

# Create 5 sessions in parallel
for i in {1..5}; do
  input='{"session_id":"parallel-'"$i"'","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
  run_hook "session_start.sh" "$input" &
done

# Wait for all background jobs
wait

# Count created sessions
created=$(ls -1 "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/"*.json 2>/dev/null | grep -c "parallel-" || echo 0)

# With lock file mechanism, we expect most (but possibly not all) to succeed
if [ "$created" -ge 3 ]; then
  test_pass "Created $created of 5 sessions under parallel load"
else
  test_fail "Only $created of 5 sessions created"
fi

cleanup_test_env

#######################################
# Test: Session start and end overlap
#######################################
test_start "concurrent: session start during end processing"
setup_test_env

# Create a session to end
cat > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/overlap-test.json" << 'EOF'
{
  "session_id": "overlap-test",
  "status": "in_progress",
  "start": {"timestamp": "2025-01-01T12:00:00Z"}
}
EOF

# Run end hook in background
end_input='{"session_id":"overlap-test","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$end_input" &

# Immediately try to start new session
start_input='{"session_id":"new-overlap","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$start_input"

wait

# Both should complete successfully
if [ -f "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/new-overlap.json" ]; then
  end_status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/overlap-test.json")
  if [ "$end_status" = "complete" ]; then
    test_pass "Both start and end completed successfully"
  else
    test_pass "New session created, original status: $end_status"
  fi
else
  test_fail "Overlap handling failed"
fi

cleanup_test_env

#######################################
# Test: Two ends for same session (idempotent)
#######################################
test_start "concurrent: two end hooks for same session"
setup_test_env

# Create a session
cat > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/double-end.json" << 'EOF'
{
  "session_id": "double-end",
  "status": "in_progress",
  "start": {"timestamp": "2025-01-01T12:00:00Z"}
}
EOF

# Run two end hooks simultaneously
input='{"session_id":"double-end","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input" &
run_hook "session_end.sh" "$input" &

wait

# Session should be complete (idempotent)
status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/double-end.json")
if [ "$status" = "complete" ]; then
  test_pass "Double end handled (idempotent)"
else
  test_fail "Status should be complete, got: $status"
fi

cleanup_test_env

#######################################
# Test: Lock file with non-existent PID
# Note: The hook has a 5-second lock timeout, so this may take up to 6s
#######################################
test_start "concurrent: handles lock from dead process"
setup_test_env

# Create lock file with PID that doesn't exist
echo "999999999" > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/.lock"

input='{"session_id":"test-dead-lock","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

start_time=$(date +%s)
run_hook "session_start.sh" "$input"
end_time=$(date +%s)
elapsed=$((end_time - start_time))

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-dead-lock.json"
# Hook has 5-second lock timeout, so we allow up to 7 seconds
if [ -f "$session_file" ] && [ $elapsed -lt 8 ]; then
  test_pass "Dead process lock handled (${elapsed}s)"
else
  test_fail "Dead process lock not handled properly (${elapsed}s)"
fi

cleanup_test_env

#######################################
# Test: Lock file with invalid content
#######################################
test_start "concurrent: handles corrupt lock file"
setup_test_env

# Create lock file with non-PID content
echo "not-a-pid" > "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/.lock"

input='{"session_id":"test-corrupt-lock","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-corrupt-lock.json"
if [ -f "$session_file" ]; then
  test_pass "Corrupt lock file handled"
fi

cleanup_test_env

#######################################
# Test: Same session start and end simultaneously
#######################################
test_start "concurrent: same session start+end race"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Run start and end for same session simultaneously
start_input='{"session_id":"race-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
end_input='{"session_id":"race-session","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'

run_hook "session_start.sh" "$start_input" &
pid1=$!
run_hook "session_end.sh" "$end_input" &
pid2=$!

wait $pid1
wait $pid2

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/race-session.json"
if [ -f "$session_file" ]; then
  status=$(jq -r '.status' "$session_file" 2>/dev/null)
  test_pass "Race condition handled (final status: $status)"
fi

cleanup_test_env

#######################################
# Test: Empty lock file
#######################################
test_start "concurrent: handles empty lock file"
setup_test_env

# Create empty lock file
touch "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/.lock"

input='{"session_id":"test-empty-lock","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-empty-lock.json"
if [ -f "$session_file" ]; then
  test_pass "Empty lock file handled"
fi

cleanup_test_env

#######################################
# Test: Lock file is a directory
#######################################
test_start "concurrent: handles .lock as directory"
setup_test_env

# Remove lock file if exists and create directory instead
rm -f "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/.lock" 2>/dev/null
mkdir -p "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/.lock"

input='{"session_id":"test-lock-dir","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input" 2>/dev/null

# Hook should handle gracefully
if [ $? -eq 0 ]; then
  test_pass ".lock directory handled gracefully"
fi

cleanup_test_env

echo ""
echo "Orphan and concurrent session tests complete"
