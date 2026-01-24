#!/usr/bin/env bash
#
# Tests for pre_compact.sh hook
#

#######################################
# Helper: Create a started session
#######################################
create_started_session_for_compact() {
  local session_id="$1"
  local session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/$session_id.json"
  local transcript_path="${2:-/tmp/test.jsonl}"

  cat > "$session_file" << EOF
{
  "schema_version": 1,
  "session_id": "$session_id",
  "transcript_path": "$transcript_path",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "cwd": "$TEST_TMPDIR",
    "source": "startup",
    "git": {
      "sha": "abc123def456",
      "branch": "main",
      "is_repo": true
    }
  }
}
EOF
}

#######################################
# Helper: Create a fake transcript file
#######################################
create_transcript() {
  local path="$1"
  echo '{"type":"user","message":"hello"}' > "$path"
  echo '{"type":"assistant","message":"hi there"}' >> "$path"
  echo '{"type":"user","message":"help me code"}' >> "$path"
}

#######################################
# Test: Basic pre-compact transcript capture
#######################################
test_start "pre_compact: captures transcript before compaction"
setup_test_env

# Copy the pre_compact hook
cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Create transcript
transcript_file="/tmp/test-compact-$$.jsonl"
create_transcript "$transcript_file"

create_started_session_for_compact "test-compact" "$transcript_file"

input='{"session_id":"test-compact","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Check snapshot was created
snapshot="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-compact_precompact_001.jsonl"
if assert_file_exists "$snapshot"; then
  # Verify content matches
  if diff -q "$transcript_file" "$snapshot" >/dev/null 2>&1; then
    test_pass "Transcript snapshot created and matches"
  else
    test_fail "Transcript content mismatch"
  fi
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Session JSON updated with compaction event
#######################################
test_start "pre_compact: updates session JSON with compaction event"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

transcript_file="/tmp/test-compact-event-$$.jsonl"
create_transcript "$transcript_file"

create_started_session_for_compact "test-event" "$transcript_file"

input='{"session_id":"test-event","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-event.json"

# Check compaction_events was added
if jq -e '.compaction_events' "$session_file" &>/dev/null; then
  trigger=$(jq -r '.compaction_events[0].trigger' "$session_file")
  snapshot=$(jq -r '.compaction_events[0].transcript_snapshot' "$session_file")

  if [ "$trigger" = "manual" ] && [ "$snapshot" = "test-event_precompact_001.jsonl" ]; then
    test_pass "Compaction event recorded correctly"
  else
    test_fail "Compaction event data incorrect (trigger: $trigger, snapshot: $snapshot)"
  fi
else
  test_fail "compaction_events not added to session JSON"
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Auto trigger type
#######################################
test_start "pre_compact: captures auto trigger type"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

transcript_file="/tmp/test-auto-$$.jsonl"
create_transcript "$transcript_file"

create_started_session_for_compact "test-auto" "$transcript_file"

input='{"session_id":"test-auto","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'","trigger":"auto"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-auto.json"
trigger=$(jq -r '.compaction_events[0].trigger' "$session_file")

if [ "$trigger" = "auto" ]; then
  test_pass "Auto trigger recorded"
else
  test_fail "Expected 'auto' trigger, got '$trigger'"
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Multiple compactions increment counter
#######################################
test_start "pre_compact: increments counter for multiple compactions"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

transcript_file="/tmp/test-multi-$$.jsonl"
create_transcript "$transcript_file"

create_started_session_for_compact "test-multi" "$transcript_file"

# First compaction
input='{"session_id":"test-multi","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Second compaction
echo '{"type":"more","data":"content"}' >> "$transcript_file"
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Third compaction
echo '{"type":"even","more":"data"}' >> "$transcript_file"
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Check all three snapshots exist
snap1="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-multi_precompact_001.jsonl"
snap2="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-multi_precompact_002.jsonl"
snap3="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-multi_precompact_003.jsonl"

if [ -f "$snap1" ] && [ -f "$snap2" ] && [ -f "$snap3" ]; then
  # Check session JSON has 3 compaction events
  session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-multi.json"
  count=$(jq '.compaction_events | length' "$session_file")

  if [ "$count" -eq 3 ]; then
    test_pass "Three compaction snapshots created"
  else
    test_fail "Expected 3 compaction events, got $count"
  fi
else
  test_fail "Not all snapshots created"
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Empty input handling
#######################################
test_start "pre_compact: handles empty input gracefully"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

echo "" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Should not create any snapshot files
snapshots=$(ls "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/"*_precompact_*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$snapshots" -eq 0 ]; then
  test_pass "No snapshot created for empty input"
else
  test_fail "Snapshot created for empty input"
fi

cleanup_test_env

#######################################
# Test: Missing session_id
#######################################
test_start "pre_compact: handles missing session_id gracefully"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

input='{"cwd":"'"$TEST_TMPDIR"'","transcript_path":"/tmp/test.jsonl","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

snapshots=$(ls "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/"*_precompact_*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$snapshots" -eq 0 ]; then
  test_pass "No snapshot created without session_id"
else
  test_fail "Snapshot created without session_id"
fi

cleanup_test_env

#######################################
# Test: Missing transcript_path
#######################################
test_start "pre_compact: handles missing transcript_path gracefully"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

create_started_session_for_compact "test-no-transcript"

input='{"session_id":"test-no-transcript","cwd":"'"$TEST_TMPDIR"'","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

snapshots=$(ls "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/"*_precompact_*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$snapshots" -eq 0 ]; then
  test_pass "No snapshot created without transcript_path"
else
  test_fail "Snapshot created without transcript_path"
fi

cleanup_test_env

#######################################
# Test: Non-existent transcript file
#######################################
test_start "pre_compact: handles non-existent transcript file"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

create_started_session_for_compact "test-missing-file"

input='{"session_id":"test-missing-file","cwd":"'"$TEST_TMPDIR"'","transcript_path":"/nonexistent/path/transcript.jsonl","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

snapshots=$(ls "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/"*_precompact_*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$snapshots" -eq 0 ]; then
  test_pass "No snapshot created for non-existent transcript"
else
  test_fail "Snapshot created for non-existent transcript"
fi

cleanup_test_env

#######################################
# Test: Empty transcript file
#######################################
test_start "pre_compact: handles empty transcript file"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Create empty transcript
transcript_file="/tmp/test-empty-$$.jsonl"
touch "$transcript_file"

create_started_session_for_compact "test-empty-transcript" "$transcript_file"

input='{"session_id":"test-empty-transcript","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

snapshots=$(ls "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/"*_precompact_*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$snapshots" -eq 0 ]; then
  test_pass "No snapshot created for empty transcript"
else
  test_fail "Snapshot created for empty transcript"
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Non-existent session file
#######################################
test_start "pre_compact: handles non-existent session file"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

transcript_file="/tmp/test-no-session-$$.jsonl"
create_transcript "$transcript_file"

# Don't create session file

input='{"session_id":"nonexistent-session","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

snapshots=$(ls "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/"*_precompact_*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$snapshots" -eq 0 ]; then
  test_pass "No snapshot created for non-existent session"
else
  test_fail "Snapshot created for non-existent session"
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Default trigger to auto
#######################################
test_start "pre_compact: defaults trigger to 'auto' when missing"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

transcript_file="/tmp/test-default-$$.jsonl"
create_transcript "$transcript_file"

create_started_session_for_compact "test-default" "$transcript_file"

# No trigger in input
input='{"session_id":"test-default","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-default.json"
trigger=$(jq -r '.compaction_events[0].trigger' "$session_file")

if [ "$trigger" = "auto" ]; then
  test_pass "Default trigger is 'auto'"
else
  test_fail "Expected default trigger 'auto', got '$trigger'"
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Timestamp recorded
#######################################
test_start "pre_compact: records timestamp in compaction event"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

transcript_file="/tmp/test-ts-$$.jsonl"
create_transcript "$transcript_file"

create_started_session_for_compact "test-timestamp" "$transcript_file"

input='{"session_id":"test-timestamp","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-timestamp.json"
timestamp=$(jq -r '.compaction_events[0].timestamp' "$session_file")

# Verify it's a valid ISO timestamp
if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  test_pass "Valid timestamp recorded: $timestamp"
else
  test_fail "Invalid timestamp: $timestamp"
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Session from git subdirectory
#######################################
test_start "pre_compact: finds session in git root from subdirectory"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

git -C "$TEST_TMPDIR" init -q
mkdir -p "$TEST_TMPDIR/src/components"

transcript_file="/tmp/test-subdir-$$.jsonl"
create_transcript "$transcript_file"

# Session file in git root
create_started_session_for_compact "test-subdir" "$transcript_file"

# Run from subdirectory
input='{"session_id":"test-subdir","cwd":"'"$TEST_TMPDIR/src/components"'","transcript_path":"'"$transcript_file"'","trigger":"manual"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Snapshot should be in git root sessions dir
snapshot="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-subdir_precompact_001.jsonl"
if [ -f "$snapshot" ]; then
  test_pass "Snapshot created in git root"
else
  test_fail "Snapshot not created in expected location"
fi

rm -f "$transcript_file"
cleanup_test_env

#######################################
# Test: Invalid JSON input
#######################################
test_start "pre_compact: handles invalid JSON gracefully"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

echo "not valid json at all" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

snapshots=$(ls "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/"*_precompact_*.jsonl 2>/dev/null | wc -l | tr -d ' ')
if [ "$snapshots" -eq 0 ]; then
  test_pass "No snapshot created for invalid JSON"
else
  test_fail "Snapshot created for invalid JSON"
fi

cleanup_test_env

#######################################
# Test: Preserves existing compaction_events
#######################################
test_start "pre_compact: preserves existing compaction_events"
setup_test_env

cp "$(dirname "$0")/../pre_compact.sh" "$TEST_TMPDIR/.claude/hooks/"
chmod +x "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

transcript_file="/tmp/test-preserve-$$.jsonl"
create_transcript "$transcript_file"

# Create session with existing compaction_events
session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-preserve.json"
cat > "$session_file" << EOF
{
  "schema_version": 1,
  "session_id": "test-preserve",
  "transcript_path": "$transcript_file",
  "status": "in_progress",
  "compaction_events": [
    {
      "timestamp": "2025-01-01T10:00:00Z",
      "trigger": "manual",
      "transcript_snapshot": "test-preserve_precompact_001.jsonl"
    }
  ],
  "start": {
    "timestamp": "2025-01-01T12:00:00Z"
  }
}
EOF

# Create fake existing snapshot
touch "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-preserve_precompact_001.jsonl"

input='{"session_id":"test-preserve","cwd":"'"$TEST_TMPDIR"'","transcript_path":"'"$transcript_file"'","trigger":"auto"}'
echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/pre_compact.sh"

# Check both events exist
count=$(jq '.compaction_events | length' "$session_file")
if [ "$count" -eq 2 ]; then
  # Check the new one is _002
  second_snapshot=$(jq -r '.compaction_events[1].transcript_snapshot' "$session_file")
  if [ "$second_snapshot" = "test-preserve_precompact_002.jsonl" ]; then
    test_pass "Existing events preserved, new event added"
  else
    test_fail "New event has wrong snapshot name: $second_snapshot"
  fi
else
  test_fail "Expected 2 compaction events, got $count"
fi

rm -f "$transcript_file"
cleanup_test_env

echo ""
echo "pre_compact.sh tests complete"
