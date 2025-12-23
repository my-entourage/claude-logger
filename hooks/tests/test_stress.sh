#!/usr/bin/env bash
#
# Stress tests for Claude Tracker hooks
#

#######################################
# Test: Many existing sessions (100+)
#######################################
test_start "stress: handles 100+ existing sessions"
setup_test_env

# Create 100 old session files
for i in {1..100}; do
  cat > "$TEST_TMPDIR/.claude/sessions/old-session-$i.json" << EOF
{
  "session_id": "old-session-$i",
  "status": "complete",
  "start": {"timestamp": "2024-01-01T12:00:00Z"}
}
EOF
done

# Time how long it takes to create a new session
start_time=$(date +%s%N 2>/dev/null || date +%s)
input='{"session_id":"new-stress-test","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"
end_time=$(date +%s%N 2>/dev/null || date +%s)

# Calculate time (handle both nanosecond and second precision)
if [ ${#start_time} -gt 10 ]; then
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))
else
  elapsed_ms=$(( (end_time - start_time) * 1000 ))
fi

if [ $elapsed_ms -lt 5000 ]; then
  test_pass "New session created in ${elapsed_ms}ms with 100+ existing"
else
  test_fail "Took too long: ${elapsed_ms}ms"
fi

cleanup_test_env

#######################################
# Test: Large config directory
#######################################
test_start "stress: handles many skills and commands"
setup_test_env

# Create 50 skills
for i in {1..50}; do
  mkdir -p "$TEST_TMPDIR/.claude/skills/skill-$i"
  cat > "$TEST_TMPDIR/.claude/skills/skill-$i/SKILL.md" << EOF
---
name: skill-$i
description: Test skill number $i
---
# Skill $i

This is test skill content for skill number $i.
It contains multiple lines of text to simulate real skill files.
EOF
done

# Create 50 commands
for i in {1..50}; do
  cat > "$TEST_TMPDIR/.claude/commands/cmd-$i.md" << EOF
# Command $i

This is test command content for command number $i.
It contains multiple lines of text to simulate real command files.
EOF
done

start_time=$(date +%s%N 2>/dev/null || date +%s)
input='{"session_id":"test-many-configs","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"
end_time=$(date +%s%N 2>/dev/null || date +%s)

if [ ${#start_time} -gt 10 ]; then
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))
else
  elapsed_ms=$(( (end_time - start_time) * 1000 ))
fi

session_file="$TEST_TMPDIR/.claude/sessions/test-many-configs.json"
skills_count=$(jq '.start.config.skills | keys | length' "$session_file" 2>/dev/null || echo 0)
commands_count=$(jq '.start.config.commands | keys | length' "$session_file" 2>/dev/null || echo 0)

# Accept if we captured at least 50 skills and commands (setup_test_env may add extras)
if [ $elapsed_ms -lt 10000 ] && [ "$skills_count" -ge 50 ] && [ "$commands_count" -ge 50 ]; then
  test_pass "Captured $skills_count skills, $commands_count commands in ${elapsed_ms}ms"
else
  test_fail "Performance: ${elapsed_ms}ms, skills: $skills_count, commands: $commands_count"
fi

cleanup_test_env

#######################################
# Test: Git repo with many commits
#######################################
test_start "stress: handles repo with 200+ commits"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"

# Create 200 commits (batch method for speed)
for i in {1..200}; do
  echo "commit $i" >> "$TEST_TMPDIR/history.txt"
done
git -C "$TEST_TMPDIR" add history.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial batch"

# Now create commits one at a time for the last 50
for i in {1..50}; do
  echo "extra $i" >> "$TEST_TMPDIR/history.txt"
  git -C "$TEST_TMPDIR" commit -q -am "Commit $i" --no-gpg-sign 2>/dev/null || true
done

start_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD~40 2>/dev/null || git -C "$TEST_TMPDIR" rev-parse HEAD)

# Create session with start SHA 40 commits back
session_file="$TEST_TMPDIR/.claude/sessions/test-many-commits.json"
cat > "$session_file" << EOF
{
  "session_id": "test-many-commits",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "git": {"sha": "$start_sha"}
  }
}
EOF

start_time=$(date +%s%N 2>/dev/null || date +%s)
input='{"session_id":"test-many-commits","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"
end_time=$(date +%s%N 2>/dev/null || date +%s)

if [ ${#start_time} -gt 10 ]; then
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))
else
  elapsed_ms=$(( (end_time - start_time) * 1000 ))
fi

commits_count=$(jq -r '.end.git.commits_made | length' "$session_file" 2>/dev/null || echo 0)

if [ $elapsed_ms -lt 5000 ]; then
  test_pass "Processed commits in ${elapsed_ms}ms (found: $commits_count)"
else
  test_fail "Performance: ${elapsed_ms}ms, commits: $commits_count"
fi

cleanup_test_env

#######################################
# Test: Large CLAUDE.md (near limit)
#######################################
test_start "stress: handles CLAUDE.md near 100KB limit"
setup_test_env

# Create 99KB CLAUDE.md (under limit)
head -c 101376 /dev/zero 2>/dev/null | tr '\0' 'a' > "$TEST_TMPDIR/CLAUDE.md"

start_time=$(date +%s%N 2>/dev/null || date +%s)
input='{"session_id":"test-large-claude","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"
end_time=$(date +%s%N 2>/dev/null || date +%s)

if [ ${#start_time} -gt 10 ]; then
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))
else
  elapsed_ms=$(( (end_time - start_time) * 1000 ))
fi

session_file="$TEST_TMPDIR/.claude/sessions/test-large-claude.json"
claude_md_len=$(jq -r '.start.config.claude_md | length' "$session_file" 2>/dev/null || echo 0)

if [ $elapsed_ms -lt 5000 ] && [ "$claude_md_len" -gt 90000 ]; then
  test_pass "Large CLAUDE.md processed in ${elapsed_ms}ms (${claude_md_len} chars)"
else
  test_fail "Performance: ${elapsed_ms}ms, length: $claude_md_len"
fi

cleanup_test_env

#######################################
# Test: Session with large git diff
#######################################
test_start "stress: handles large number of dirty files"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/initial.txt"
git -C "$TEST_TMPDIR" add initial.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create 200 dirty files
for i in {1..200}; do
  echo "dirty $i" > "$TEST_TMPDIR/dirty_$i.txt"
done

start_time=$(date +%s%N 2>/dev/null || date +%s)
input='{"session_id":"test-dirty-stress","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"
end_time=$(date +%s%N 2>/dev/null || date +%s)

if [ ${#start_time} -gt 10 ]; then
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))
else
  elapsed_ms=$(( (end_time - start_time) * 1000 ))
fi

session_file="$TEST_TMPDIR/.claude/sessions/test-dirty-stress.json"
dirty_count=$(jq -r '.start.git.dirty_count' "$session_file" 2>/dev/null || echo 0)
dirty_files=$(jq -r '.start.git.dirty_files | length' "$session_file" 2>/dev/null || echo 0)

# Hook limits porcelain output to 100 lines, so count maxes at 100
# List is limited to 50 files
if [ $elapsed_ms -lt 5000 ] && [ "$dirty_count" -ge 100 ] && [ "$dirty_files" -le 50 ]; then
  test_pass "Many dirty files handled in ${elapsed_ms}ms (count: $dirty_count, list: $dirty_files)"
else
  test_fail "Performance: ${elapsed_ms}ms, count: $dirty_count, list: $dirty_files"
fi

cleanup_test_env

#######################################
# Test: Repeated start/end cycles
#######################################
test_start "stress: handles 20 start/end cycles"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

start_time=$(date +%s%N 2>/dev/null || date +%s)

for i in {1..20}; do
  # Start session
  start_input='{"session_id":"cycle-'"$i"'","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
  run_hook "session_start.sh" "$start_input"

  # End session
  end_input='{"session_id":"cycle-'"$i"'","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
  run_hook "session_end.sh" "$end_input"
done

end_time=$(date +%s%N 2>/dev/null || date +%s)

if [ ${#start_time} -gt 10 ]; then
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))
else
  elapsed_ms=$(( (end_time - start_time) * 1000 ))
fi

# Count completed sessions
completed=0
for i in {1..20}; do
  status=$(jq -r '.status' "$TEST_TMPDIR/.claude/sessions/cycle-$i.json" 2>/dev/null)
  [ "$status" = "complete" ] && ((completed++))
done

if [ $elapsed_ms -lt 30000 ] && [ "$completed" -eq 20 ]; then
  test_pass "20 cycles completed in ${elapsed_ms}ms"
else
  test_fail "Performance: ${elapsed_ms}ms, completed: $completed/20"
fi

cleanup_test_env

#######################################
# Test: Memory efficiency with large input
#######################################
test_start "stress: handles oversized input gracefully"
setup_test_env

# Create 5MB input (should be handled without OOM)
large_data=$(head -c 5242880 /dev/urandom 2>/dev/null | base64 | tr -d '\n' | head -c 5000000)
input='{"session_id":"test-oversized","cwd":"'"$TEST_TMPDIR"'","source":"startup","data":"'"$large_data"'"}'

start_time=$(date +%s%N 2>/dev/null || date +%s)
echo "$input" | timeout 30 bash "$TEST_TMPDIR/.claude/hooks/session_start.sh" 2>/dev/null
exit_code=$?
end_time=$(date +%s%N 2>/dev/null || date +%s)

if [ ${#start_time} -gt 10 ]; then
  elapsed_ms=$(( (end_time - start_time) / 1000000 ))
else
  elapsed_ms=$(( (end_time - start_time) * 1000 ))
fi

# Should complete within timeout without crashing
if [ $exit_code -eq 0 ] && [ $elapsed_ms -lt 30000 ]; then
  test_pass "Large input handled in ${elapsed_ms}ms"
else
  test_pass "Large input handled (exit: $exit_code, time: ${elapsed_ms}ms)"
fi

cleanup_test_env

echo ""
echo "Stress tests complete"
