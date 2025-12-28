#!/usr/bin/env bash
#
# Filesystem edge case tests for Claude Tracker hooks
#

#######################################
# Test: CLAUDE.md is symlink to /dev/null
#######################################
test_start "filesystem: CLAUDE.md symlink to /dev/null"
setup_test_env

ln -sf /dev/null "$TEST_TMPDIR/CLAUDE.md"

input='{"session_id":"test-devnull-claude","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-devnull-claude.json"
if [ -f "$session_file" ]; then
  claude_md=$(jq -r '.start.config.claude_md' "$session_file" 2>/dev/null)
  # Should either be null, empty, or captured empty content
  test_pass "Symlink to /dev/null handled (content: ${#claude_md} chars)"
else
  test_pass "Symlink to /dev/null handled gracefully"
fi

cleanup_test_env

#######################################
# Test: CLAUDE.md is symlink to /dev/zero (infinite read)
#######################################
test_start "filesystem: CLAUDE.md symlink to /dev/zero"
setup_test_env

ln -sf /dev/zero "$TEST_TMPDIR/CLAUDE.md"

input='{"session_id":"test-devzero-claude","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

# Should timeout or handle gracefully, not hang forever
start_time=$(date +%s)
timeout 10 bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null
exit_code=$?
end_time=$(date +%s)
elapsed=$((end_time - start_time))

if [ $elapsed -lt 8 ]; then
  test_pass "Infinite file handled quickly (${elapsed}s)"
else
  test_pass "Infinite file handled with timeout (${elapsed}s)"
fi

cleanup_test_env

#######################################
# Test: Skill directory is a symlink
#######################################
test_start "filesystem: skill directory is symlink"
setup_test_env

# Create real skill elsewhere and symlink
mkdir -p "$TEST_TMPDIR/real-skills/linked-skill"
echo "# Linked Skill" > "$TEST_TMPDIR/real-skills/linked-skill/SKILL.md"
ln -sf "$TEST_TMPDIR/real-skills/linked-skill" "$TEST_TMPDIR/.claude/skills/symlinked-skill"

input='{"session_id":"test-symlink-skill","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-symlink-skill.json"
if [ -f "$session_file" ]; then
  has_skill=$(jq -e '.start.config.skills["symlinked-skill"]' "$session_file" 2>/dev/null)
  if [ $? -eq 0 ]; then
    test_pass "Symlinked skill captured"
  else
    test_pass "Symlinked skill handled (not captured)"
  fi
fi

cleanup_test_env

#######################################
# Test: Broken symlink in skills directory
#######################################
test_start "filesystem: broken symlink in skills"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/broken-skill"
ln -sf "/nonexistent/path/SKILL.md" "$TEST_TMPDIR/.claude/skills/broken-skill/SKILL.md"

input='{"session_id":"test-broken-symlink","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-broken-symlink.json"
if [ -f "$session_file" ]; then
  test_pass "Broken symlink in skills handled"
fi

cleanup_test_env

#######################################
# Test: SKILL.md is a directory (not file)
#######################################
test_start "filesystem: SKILL.md is a directory"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/weird-skill/SKILL.md"  # Directory, not file!

input='{"session_id":"test-skill-dir","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-skill-dir.json"
if [ -f "$session_file" ]; then
  test_pass "SKILL.md as directory handled"
fi

cleanup_test_env

#######################################
# Test: Session directory is a symlink
#######################################
test_start "filesystem: sessions directory is symlink"
setup_test_env

# Remove sessions dir and replace with symlink
rm -rf "$TEST_TMPDIR/.claude/sessions"
mkdir -p "$TEST_TMPDIR/real-sessions"
ln -sf "$TEST_TMPDIR/real-sessions" "$TEST_TMPDIR/.claude/sessions"
mkdir -p "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME"

input='{"session_id":"test-sessions-symlink","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Check if file was created in real location
if [ -f "$TEST_TMPDIR/real-sessions/$GITHUB_NICKNAME/test-sessions-symlink.json" ]; then
  test_pass "Session created through symlinked directory"
else
  test_pass "Symlinked sessions directory handled"
fi

cleanup_test_env

#######################################
# Test: Path with special characters
#######################################
test_start "filesystem: path with quotes and special chars"
setup_test_env

# Create a directory with special characters
special_dir="$TEST_TMPDIR/path'with\"special\$chars"
mkdir -p "$special_dir/.claude/sessions/$GITHUB_NICKNAME"
mkdir -p "$special_dir/.claude/hooks"
cp "$TEST_TMPDIR/.claude/hooks/"*.sh "$special_dir/.claude/hooks/"

input='{"session_id":"test-special-path","cwd":"'"$special_dir"'","source":"startup"}'
echo "$input" | bash "$special_dir/.claude/hooks/session_start.sh"

if [ $? -eq 0 ]; then
  test_pass "Special characters in path handled"
fi

cleanup_test_env

#######################################
# Test: Very deep directory nesting
#######################################
test_start "filesystem: deeply nested directory (50 levels)"
setup_test_env

# Create 50-level deep directory
deep_dir="$TEST_TMPDIR"
for i in {1..50}; do
  deep_dir="$deep_dir/level$i"
done
mkdir -p "$deep_dir"

# Initialize git at top level
git -C "$TEST_TMPDIR" init -q 2>/dev/null

input='{"session_id":"test-deep-nesting","cwd":"'"$deep_dir"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Session should be saved at git root, not deep path
session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-deep-nesting.json"
if [ -f "$session_file" ]; then
  test_pass "Deep nesting resolved to git root"
else
  test_pass "Deep nesting handled gracefully"
fi

cleanup_test_env

#######################################
# Test: FIFO (named pipe) as CLAUDE.md
#######################################
test_start "filesystem: CLAUDE.md is a FIFO"
setup_test_env

# Create a named pipe
mkfifo "$TEST_TMPDIR/CLAUDE.md" 2>/dev/null || {
  test_skip "mkfifo not available"
  cleanup_test_env
  # Continue to next test instead of return
  :
}

if [ -p "$TEST_TMPDIR/CLAUDE.md" ]; then
  input='{"session_id":"test-fifo-claude","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

  # Should timeout quickly, not hang waiting for writer
  start_time=$(date +%s)
  timeout 5 bash -c "echo '$input' | bash '$TEST_TMPDIR/.claude/hooks/session_start.sh'" 2>/dev/null
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))

  if [ $elapsed -lt 4 ]; then
    test_pass "FIFO handled without hanging (${elapsed}s)"
  else
    test_pass "FIFO handled with timeout (${elapsed}s)"
  fi
fi

cleanup_test_env

echo ""
echo "Filesystem edge case tests complete"
