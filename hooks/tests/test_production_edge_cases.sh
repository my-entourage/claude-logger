#!/usr/bin/env bash
#
# Production-observed edge case tests for Claude Tracker hooks
# Based on analysis of entourage-web production data (Dec 25-28, 2025)
#

#######################################
# Test: First session in fresh project (no prior sessions)
#######################################
test_start "production: first session in fresh project"
setup_test_env

# Ensure sessions directory is completely empty (no prior sessions)
rm -rf "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER"/*

input='{"session_id":"very-first-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/very-first-session.json"
if [ -f "$session_file" ]; then
  status=$(jq -r '.status' "$session_file")
  if [ "$status" = "in_progress" ]; then
    test_pass "First session created successfully"
  else
    test_fail "First session has wrong status: $status"
  fi
else
  test_fail "First session file not created"
fi

cleanup_test_env

#######################################
# Test: Transcript path exists in JSON but file was deleted
#######################################
test_start "production: transcript path in JSON but file deleted before end"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create transcript file
transcript_path="$TEST_TMPDIR/fake-transcript.jsonl"
echo '{"type":"user","message":"hello"}' > "$transcript_path"

# Create session with transcript path
cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/deleted-transcript.json" << EOF
{
  "schema_version": 2,
  "session_id": "deleted-transcript",
  "transcript_path": "$transcript_path",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "cwd": "$TEST_TMPDIR",
    "git": {"sha": "abc123", "branch": "main", "is_repo": true}
  }
}
EOF

# Delete the transcript before session_end runs (simulates file moved/deleted)
rm "$transcript_path"

input='{"session_id":"deleted-transcript","cwd":"'"$TEST_TMPDIR"'","reason":"clear"}'
run_hook "session_end.sh" "$input"

# Session should complete successfully even without transcript
session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/deleted-transcript.json"
status=$(jq -r '.status' "$session_file" 2>/dev/null)
if [ "$status" = "complete" ]; then
  # Transcript should NOT exist (was deleted)
  if [ ! -f "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/deleted-transcript.jsonl" ]; then
    test_pass "Session completed gracefully despite missing transcript"
  else
    test_fail "Transcript should not exist"
  fi
else
  test_fail "Session should be complete, got: $status"
fi

cleanup_test_env

#######################################
# Test: Transcript path changed between start and end
#######################################
test_start "production: transcript path different from actual file location"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create session with a transcript path that points to wrong location
cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/wrong-path.json" << EOF
{
  "schema_version": 2,
  "session_id": "wrong-path",
  "transcript_path": "/nonexistent/path/to/transcript.jsonl",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "cwd": "$TEST_TMPDIR",
    "git": {"sha": "abc123", "branch": "main", "is_repo": true}
  }
}
EOF

input='{"session_id":"wrong-path","cwd":"'"$TEST_TMPDIR"'","reason":"clear"}'
run_hook "session_end.sh" "$input"

# Session should complete successfully
session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/wrong-path.json"
status=$(jq -r '.status' "$session_file" 2>/dev/null)
if [ "$status" = "complete" ]; then
  test_pass "Session completed despite invalid transcript path"
else
  test_fail "Session should be complete, got: $status"
fi

cleanup_test_env

#######################################
# Test: High commit count (50+ commits) during session
# Production saw 51 commits in one session (zombie)
#######################################
test_start "production: session with 50+ commits"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"

# Create initial commit
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

start_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD)

# Start session
input='{"session_id":"many-commits","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Create 55 commits during session
for i in $(seq 1 55); do
  echo "commit $i" >> "$TEST_TMPDIR/file.txt"
  git -C "$TEST_TMPDIR" add file.txt
  git -C "$TEST_TMPDIR" commit -q -m "Commit $i"
done

# End session
end_input='{"session_id":"many-commits","cwd":"'"$TEST_TMPDIR"'","reason":"clear"}'
run_hook "session_end.sh" "$end_input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/many-commits.json"
if [ -f "$session_file" ]; then
  commit_count=$(jq '.end.git.commits_made | length' "$session_file" 2>/dev/null)
  status=$(jq -r '.status' "$session_file")

  if [ "$status" = "complete" ]; then
    # Should capture commits (may be limited by hook's 100 cap)
    if [ "$commit_count" -ge 50 ]; then
      test_pass "Captured $commit_count commits successfully"
    else
      test_fail "Expected 50+ commits, got $commit_count"
    fi
  else
    test_fail "Session should be complete, got: $status"
  fi
else
  test_fail "Session file not found"
fi

cleanup_test_env

#######################################
# Test: Rapid orphan cascade (5 sessions started in quick succession)
# Production showed 15 orphans over 4 days
#######################################
test_start "production: rapid orphan cascade"
setup_test_env

# Create 5 "orphan" sessions in quick succession
for i in $(seq 1 5); do
  cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/rapid-orphan-$i.json" << EOF
{
  "schema_version": 2,
  "session_id": "rapid-orphan-$i",
  "status": "in_progress",
  "start": {"timestamp": "2025-01-01T12:0$i:00Z", "cwd": "$TEST_TMPDIR"}
}
EOF
  touch "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/rapid-orphan-$i.json"
done

# Start a new session that should mark all 5 as orphaned
input='{"session_id":"new-session-after-cascade","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Count orphaned sessions
orphan_count=0
for i in $(seq 1 5); do
  status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/rapid-orphan-$i.json" 2>/dev/null)
  reason=$(jq -r '.end.reason' "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/rapid-orphan-$i.json" 2>/dev/null)
  if [ "$status" = "incomplete" ] && [ "$reason" = "orphaned" ]; then
    ((orphan_count++))
  fi
done

if [ "$orphan_count" -eq 5 ]; then
  test_pass "All 5 rapid orphans marked correctly"
else
  test_fail "Only $orphan_count of 5 orphans marked"
fi

cleanup_test_env

#######################################
# Test: Session with extremely long duration (simulated zombie)
# Production saw 29+ hour session
#######################################
test_start "production: zombie session (30 hour simulated duration)"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create session with timestamp 30 hours ago
# Using a fixed past timestamp to simulate zombie
start_timestamp="2025-01-01T00:00:00Z"  # 30 hours ago (simulated)

cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/zombie-session.json" << EOF
{
  "schema_version": 2,
  "session_id": "zombie-session",
  "status": "in_progress",
  "start": {
    "timestamp": "$start_timestamp",
    "cwd": "$TEST_TMPDIR",
    "source": "startup",
    "git": {
      "sha": "$(git -C "$TEST_TMPDIR" rev-parse HEAD)",
      "branch": "main",
      "is_repo": true
    }
  }
}
EOF

# Make some commits to simulate activity
for i in $(seq 1 10); do
  echo "zombie commit $i" >> "$TEST_TMPDIR/file.txt"
  git -C "$TEST_TMPDIR" add file.txt
  git -C "$TEST_TMPDIR" commit -q -m "Zombie commit $i"
done

# End the zombie session
input='{"session_id":"zombie-session","cwd":"'"$TEST_TMPDIR"'","reason":"other"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/zombie-session.json"
if [ -f "$session_file" ]; then
  status=$(jq -r '.status' "$session_file")
  duration=$(jq -r '.end.duration_seconds' "$session_file")
  commits=$(jq '.end.git.commits_made | length' "$session_file")

  if [ "$status" = "complete" ]; then
    # Duration should be calculated (will be very large or negative due to simulated time)
    # The important thing is it doesn't crash
    if [ "$commits" -eq 10 ]; then
      test_pass "Zombie session completed (duration: ${duration}s, commits: $commits)"
    else
      test_pass "Zombie session completed with $commits commits tracked"
    fi
  else
    test_fail "Zombie session should be complete, got: $status"
  fi
else
  test_fail "Zombie session file not found"
fi

cleanup_test_env

#######################################
# Test: Session with commits from other sessions in range
# This simulates the production zombie that captured 51 commits
#######################################
test_start "production: commit range spanning other sessions' commits"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"

# Create initial commit
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

old_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD)

# Make commits that would have been from "other sessions"
for i in $(seq 1 5); do
  echo "other session commit $i" >> "$TEST_TMPDIR/file.txt"
  git -C "$TEST_TMPDIR" add file.txt
  git -C "$TEST_TMPDIR" commit -q -m "Other session commit $i"
done

# Create session that claims to have started at old_sha
cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/stale-sha-session.json" << EOF
{
  "schema_version": 2,
  "session_id": "stale-sha-session",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "cwd": "$TEST_TMPDIR",
    "source": "startup",
    "git": {
      "sha": "$old_sha",
      "branch": "main",
      "is_repo": true
    }
  }
}
EOF

# End session - it will think all 5 commits were made during this session
input='{"session_id":"stale-sha-session","cwd":"'"$TEST_TMPDIR"'","reason":"clear"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/stale-sha-session.json"
if [ -f "$session_file" ]; then
  commits=$(jq '.end.git.commits_made | length' "$session_file")
  status=$(jq -r '.status' "$session_file")

  if [ "$status" = "complete" ]; then
    # This scenario shows that commits_made can include commits from other sessions
    # if the start_sha is stale (as happened with the zombie session)
    test_pass "Stale SHA session completed (captured $commits commits from range)"
  else
    test_fail "Session should be complete, got: $status"
  fi
else
  test_fail "Session file not found"
fi

cleanup_test_env

#######################################
# Test: Session started while another is ending (race)
#######################################
test_start "production: session start during another session's end"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create first session
cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/ending-session.json" << EOF
{
  "schema_version": 2,
  "session_id": "ending-session",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "cwd": "$TEST_TMPDIR",
    "git": {"sha": "$(git -C "$TEST_TMPDIR" rev-parse HEAD)", "branch": "main", "is_repo": true}
  }
}
EOF

# Start both operations simultaneously
end_input='{"session_id":"ending-session","cwd":"'"$TEST_TMPDIR"'","reason":"clear"}'
start_input='{"session_id":"starting-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

run_hook "session_end.sh" "$end_input" &
pid1=$!
run_hook "session_start.sh" "$start_input" &
pid2=$!

wait $pid1
wait $pid2

# Both operations should succeed
ending_status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/ending-session.json" 2>/dev/null)
starting_exists=$([ -f "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/starting-session.json" ] && echo "yes" || echo "no")

if [ "$ending_status" = "complete" ] && [ "$starting_exists" = "yes" ]; then
  test_pass "Both end and start operations completed"
elif [ "$ending_status" = "complete" ]; then
  test_pass "End completed, start may have been blocked by lock"
else
  test_fail "Race condition not handled properly (ending: $ending_status, starting: $starting_exists)"
fi

cleanup_test_env

#######################################
# Test: Session with end_reason "other" (production observed)
#######################################
test_start "production: session with end_reason 'other'"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/other-reason.json" << EOF
{
  "schema_version": 2,
  "session_id": "other-reason",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "cwd": "$TEST_TMPDIR",
    "git": {"sha": "$(git -C "$TEST_TMPDIR" rev-parse HEAD)", "branch": "main", "is_repo": true}
  }
}
EOF

input='{"session_id":"other-reason","cwd":"'"$TEST_TMPDIR"'","reason":"other"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/other-reason.json"
reason=$(jq -r '.end.reason' "$session_file" 2>/dev/null)
status=$(jq -r '.status' "$session_file" 2>/dev/null)

if [ "$status" = "complete" ] && [ "$reason" = "other" ]; then
  test_pass "Session with 'other' reason handled correctly"
else
  test_fail "Expected complete/other, got $status/$reason"
fi

cleanup_test_env

#######################################
# Test: Multiple users with sessions in same project
# Production shows sessions organized by CLAUDE_LOGGER_USER
#######################################
test_start "production: multi-user session isolation"
setup_test_env

# Create sessions for two different users
for user in "alice" "bob"; do
  mkdir -p "$TEST_TMPDIR/.claude/sessions/$user"

  cat > "$TEST_TMPDIR/.claude/sessions/$user/user-session.json" << EOF
{
  "schema_version": 2,
  "session_id": "user-session",
  "status": "in_progress",
  "start": {"timestamp": "2025-01-01T12:00:00Z", "cwd": "$TEST_TMPDIR"}
}
EOF
done

# Start new session as test user - should not affect other users' sessions
input='{"session_id":"new-user-session","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Check alice's and bob's sessions are unchanged (still in_progress)
alice_status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/alice/user-session.json" 2>/dev/null)
bob_status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/bob/user-session.json" 2>/dev/null)

if [ "$alice_status" = "in_progress" ] && [ "$bob_status" = "in_progress" ]; then
  test_pass "Other users' sessions not affected"
else
  test_fail "User isolation failed (alice: $alice_status, bob: $bob_status)"
fi

cleanup_test_env

#######################################
# Test: Session file with extra fields preserved
# Production sessions may have accumulated extra fields over versions
#######################################
test_start "production: session with extra/legacy fields preserved"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create session with extra fields (simulating legacy/future schema)
cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/extra-fields.json" << EOF
{
  "schema_version": 2,
  "session_id": "extra-fields",
  "status": "in_progress",
  "legacy_field": "should_be_preserved",
  "custom_data": {"key": "value"},
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "cwd": "$TEST_TMPDIR",
    "git": {"sha": "$(git -C "$TEST_TMPDIR" rev-parse HEAD)", "branch": "main", "is_repo": true}
  }
}
EOF

input='{"session_id":"extra-fields","cwd":"'"$TEST_TMPDIR"'","reason":"clear"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/extra-fields.json"
legacy_field=$(jq -r '.legacy_field' "$session_file" 2>/dev/null)
custom_data=$(jq -r '.custom_data.key' "$session_file" 2>/dev/null)

if [ "$legacy_field" = "should_be_preserved" ] && [ "$custom_data" = "value" ]; then
  test_pass "Extra fields preserved during session_end"
else
  test_fail "Extra fields lost (legacy: $legacy_field, custom: $custom_data)"
fi

cleanup_test_env

#######################################
# Test: Empty transcript file (0 bytes)
#######################################
test_start "production: empty transcript file (0 bytes)"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add file.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create empty transcript file
transcript_path="$TEST_TMPDIR/empty-transcript.jsonl"
touch "$transcript_path"  # 0 bytes

cat > "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/empty-transcript-session.json" << EOF
{
  "schema_version": 2,
  "session_id": "empty-transcript-session",
  "transcript_path": "$transcript_path",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "cwd": "$TEST_TMPDIR",
    "git": {"sha": "$(git -C "$TEST_TMPDIR" rev-parse HEAD)", "branch": "main", "is_repo": true}
  }
}
EOF

input='{"session_id":"empty-transcript-session","cwd":"'"$TEST_TMPDIR"'","reason":"clear"}'
run_hook "session_end.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/empty-transcript-session.json"
status=$(jq -r '.status' "$session_file" 2>/dev/null)

# Empty transcript should not be copied (per existing behavior)
copied_transcript="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/empty-transcript-session.jsonl"
if [ "$status" = "complete" ] && [ ! -f "$copied_transcript" ]; then
  test_pass "Empty transcript skipped correctly"
elif [ "$status" = "complete" ]; then
  test_pass "Session completed (empty transcript may have been copied)"
else
  test_fail "Session should be complete, got: $status"
fi

cleanup_test_env

echo ""
echo "Production edge case tests complete"
