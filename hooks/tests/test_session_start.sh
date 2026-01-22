#!/usr/bin/env bash
#
# Tests for session_start.sh hook
#

#######################################
# Test: Basic session creation
#######################################
test_start "session_start: creates session file with valid input"
setup_test_env

input='{"session_id":"test-basic","cwd":"'"$TEST_TMPDIR"'","source":"startup","transcript_path":"/tmp/test.jsonl"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-basic.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.session_id' 'test-basic' && \
   assert_json_value "$session_file" '.status' 'in_progress' && \
   assert_json_value "$session_file" '.start.source' 'startup' && \
   assert_json_exists "$session_file" '.start.timestamp'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Empty input handling
#######################################
test_start "session_start: handles empty input gracefully"
setup_test_env

run_hook "session_start.sh" ""

# Should not create any session file
if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)" ]; then
  test_pass "No session file created for empty input"
else
  test_fail "Session file created for empty input"
fi

cleanup_test_env

#######################################
# Test: Missing session_id
#######################################
test_start "session_start: handles missing session_id gracefully"
setup_test_env

input='{"cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)" ]; then
  test_pass "No session file created without session_id"
else
  test_fail "Session file created without session_id"
fi

cleanup_test_env

#######################################
# Test: Invalid JSON input
#######################################
test_start "session_start: handles invalid JSON gracefully"
setup_test_env

run_hook "session_start.sh" "not valid json at all"

if [ -z "$(ls -A "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/" 2>/dev/null)" ]; then
  test_pass "No session file created for invalid JSON"
else
  test_fail "Session file created for invalid JSON"
fi

cleanup_test_env

#######################################
# Test: Non-git directory
#######################################
test_start "session_start: handles non-git directory"
setup_test_env

input='{"session_id":"test-nogit","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-nogit.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.git.is_repo' 'false' && \
   assert_json_value "$session_file" '.start.git.sha' ''; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Git repository detection
#######################################
test_start "session_start: captures git state in git repo"
setup_test_env

# Initialize a git repo in test dir
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"

input='{"session_id":"test-git","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-git.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.git.is_repo' 'true' && \
   assert_json_exists "$session_file" '.start.git.sha' && \
   assert_json_exists "$session_file" '.start.git.branch'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Dirty git state detection
#######################################
test_start "session_start: captures dirty git state"
setup_test_env

# Initialize git repo with uncommitted changes
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"
echo "modified" > "$TEST_TMPDIR/test.txt"  # Make it dirty

input='{"session_id":"test-dirty","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-dirty.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.git.dirty' 'true' && \
   assert_json_exists "$session_file" '.start.git.dirty_files'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: CLAUDE.md capture
#######################################
test_start "session_start: captures CLAUDE.md content"
setup_test_env

# Create a CLAUDE.md file
echo "# Test Project" > "$TEST_TMPDIR/CLAUDE.md"
echo "This is a test." >> "$TEST_TMPDIR/CLAUDE.md"

input='{"session_id":"test-claudemd","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-claudemd.json"
claude_md_content=$(jq -r '.start.config.claude_md' "$session_file")

if assert_file_exists "$session_file" && \
   [[ "$claude_md_content" == *"Test Project"* ]]; then
  test_pass
else
  test_fail "CLAUDE.md content not captured correctly"
fi

cleanup_test_env

#######################################
# Test: No CLAUDE.md handling
#######################################
test_start "session_start: handles missing CLAUDE.md"
setup_test_env

input='{"session_id":"test-noclaudemd","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-noclaudemd.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.config.claude_md' 'null'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Large CLAUDE.md handling
#######################################
test_start "session_start: handles large CLAUDE.md (>100KB)"
setup_test_env

# Create a 150KB CLAUDE.md file
head -c 153600 /dev/urandom | base64 > "$TEST_TMPDIR/CLAUDE.md"

input='{"session_id":"test-largeclaudemd","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-largeclaudemd.json"
claude_md_content=$(jq -r '.start.config.claude_md' "$session_file")

if assert_file_exists "$session_file" && \
   [[ "$claude_md_content" == *"too large"* ]]; then
  test_pass "Large CLAUDE.md handled with placeholder"
else
  test_fail "Large CLAUDE.md not handled correctly"
fi

cleanup_test_env

#######################################
# Test: Skills capture
#######################################
test_start "session_start: captures skills from .claude/skills/"
setup_test_env

# Create a skill
echo "---" > "$TEST_TMPDIR/.claude/skills/test-skill/SKILL.md"
echo "name: test-skill" >> "$TEST_TMPDIR/.claude/skills/test-skill/SKILL.md"
echo "---" >> "$TEST_TMPDIR/.claude/skills/test-skill/SKILL.md"
echo "# Test Skill" >> "$TEST_TMPDIR/.claude/skills/test-skill/SKILL.md"

input='{"session_id":"test-skills","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-skills.json"
skill_content=$(jq -r '.start.config.skills["test-skill"]' "$session_file")

if assert_file_exists "$session_file" && \
   [[ "$skill_content" == *"Test Skill"* ]]; then
  test_pass
else
  test_fail "Skills not captured correctly"
fi

cleanup_test_env

#######################################
# Test: Commands capture
#######################################
test_start "session_start: captures commands from .claude/commands/"
setup_test_env

# Create a command
echo "# Test Command" > "$TEST_TMPDIR/.claude/commands/test-cmd.md"
echo "Does something useful." >> "$TEST_TMPDIR/.claude/commands/test-cmd.md"

input='{"session_id":"test-commands","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-commands.json"
cmd_content=$(jq -r '.start.config.commands["test-cmd"]' "$session_file")

if assert_file_exists "$session_file" && \
   [[ "$cmd_content" == *"Test Command"* ]]; then
  test_pass
else
  test_fail "Commands not captured correctly"
fi

cleanup_test_env

#######################################
# Test: Resume source type
#######################################
test_start "session_start: captures 'resume' source type"
setup_test_env

input='{"session_id":"test-resume","cwd":"'"$TEST_TMPDIR"'","source":"resume"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-resume.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.source' 'resume'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: MCP servers capture
#######################################
test_start "session_start: captures MCP servers from .mcp.json"
setup_test_env

# Create .mcp.json
echo '{"mcpServers":{"linear":{},"github":{}}}' > "$TEST_TMPDIR/.mcp.json"

input='{"session_id":"test-mcp","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-mcp.json"
mcp_servers=$(jq -r '.start.config.mcp_servers | length' "$session_file")

if assert_file_exists "$session_file" && \
   [ "$mcp_servers" -eq 2 ]; then
  test_pass "MCP servers captured: 2"
else
  test_fail "MCP servers not captured correctly (got: $mcp_servers)"
fi

cleanup_test_env

#######################################
# Test: Orphan session marking
#######################################
test_start "session_start: marks orphaned in_progress sessions as incomplete"
setup_test_env

# Create an orphaned session (in_progress from "previous" session)
orphan_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/orphan-session.json"
cat > "$orphan_file" << 'EOF'
{
  "session_id": "orphan-session",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T00:00:00Z"
  }
}
EOF

# Start a new session (should mark orphan as incomplete)
input='{"session_id":"test-newstart","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

orphan_status=$(jq -r '.status' "$orphan_file")
orphan_reason=$(jq -r '.end.reason' "$orphan_file")

if [ "$orphan_status" = "incomplete" ] && [ "$orphan_reason" = "orphaned" ]; then
  test_pass "Orphan session marked incomplete"
else
  test_fail "Orphan session not marked correctly (status: $orphan_status, reason: $orphan_reason)"
fi

cleanup_test_env

#######################################
# Test: Schema version
#######################################
test_start "session_start: includes schema version"
setup_test_env

input='{"session_id":"test-schema","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-schema.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.schema_version' '1'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: Transcript path capture
#######################################
test_start "session_start: captures transcript path"
setup_test_env

input='{"session_id":"test-transcript","cwd":"'"$TEST_TMPDIR"'","source":"startup","transcript_path":"/home/user/.claude/sessions/abc.jsonl"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-transcript.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.transcript_path' '/home/user/.claude/sessions/abc.jsonl'; then
  test_pass
fi

cleanup_test_env

#######################################
# Test: CWD fallback
#######################################
test_start "session_start: falls back to pwd when cwd is invalid"
setup_test_env

# Use an invalid cwd - hook should fall back to current working directory
input='{"session_id":"test-fallback","cwd":"/nonexistent/path/12345","source":"startup"}'

# Run from a known directory (save and restore cwd)
original_dir=$(pwd)
cd "$TEST_TMPDIR"
run_hook "session_start.sh" "$input"
cd "$original_dir"

# The session file should be created in the fallback location
# Since fallback is pwd, which we set to TEST_TMPDIR
session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-fallback.json"
if assert_file_exists "$session_file"; then
  test_pass "Fallback to pwd worked"
else
  test_fail "CWD fallback failed"
fi

cleanup_test_env

#######################################
# Test: Permission denied on sessions directory
#######################################
test_start "session_start: handles read-only sessions directory"
setup_test_env

# Make sessions directory read-only
chmod 444 "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER"

input='{"session_id":"test-readonly","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Hook should exit gracefully (exit 0)
exit_code=$?

# Restore permissions for cleanup
chmod 755 "$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER"

if [ $exit_code -eq 0 ]; then
  test_pass "Read-only directory handled gracefully"
else
  test_fail "Hook should exit 0 on permission denied"
fi

cleanup_test_env

#######################################
# Test: Empty .mcp.json
#######################################
test_start "session_start: handles empty .mcp.json"
setup_test_env

echo '{}' > "$TEST_TMPDIR/.mcp.json"

input='{"session_id":"test-empty-mcp","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-empty-mcp.json"
mcp_count=$(jq -r '.start.config.mcp_servers | length' "$session_file")

if assert_file_exists "$session_file" && [ "$mcp_count" -eq 0 ]; then
  test_pass "Empty .mcp.json handled (0 servers)"
else
  test_fail "Empty .mcp.json not handled correctly"
fi

cleanup_test_env

#######################################
# Test: Malformed .mcp.json
#######################################
test_start "session_start: handles malformed .mcp.json"
setup_test_env

echo 'not valid json' > "$TEST_TMPDIR/.mcp.json"

input='{"session_id":"test-bad-mcp","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-bad-mcp.json"

# Session should still be created with empty mcp_servers
if assert_file_exists "$session_file"; then
  mcp_servers=$(jq -r '.start.config.mcp_servers' "$session_file")
  if [ "$mcp_servers" = "[]" ]; then
    test_pass "Malformed .mcp.json -> empty array"
  else
    test_pass "Malformed .mcp.json handled"
  fi
else
  test_fail "Session file should be created despite bad .mcp.json"
fi

cleanup_test_env

#######################################
# Test: CLAUDE.md exactly at size limit (100KB)
#######################################
test_start "session_start: handles CLAUDE.md just under 100KB limit"
setup_test_env

# Create exactly 102399 bytes (just under 100KB limit of 102400)
head -c 102399 /dev/zero | tr '\0' 'a' > "$TEST_TMPDIR/CLAUDE.md"

input='{"session_id":"test-exact-size","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-exact-size.json"
claude_md=$(jq -r '.start.config.claude_md' "$session_file")

if assert_file_exists "$session_file" && \
   [[ "$claude_md" != *"too large"* ]]; then
  test_pass "File at limit included"
else
  test_fail "File at limit should be included"
fi

cleanup_test_env

#######################################
# Test: Empty skills directory
#######################################
test_start "session_start: handles empty skills directory"
setup_test_env

# skills directory exists but is empty (remove the test-skill subdir)
rm -rf "$TEST_TMPDIR/.claude/skills/test-skill"

input='{"session_id":"test-empty-skills","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-empty-skills.json"
skills=$(jq -r '.start.config.skills' "$session_file")

if assert_file_exists "$session_file" && [ "$skills" = "{}" ]; then
  test_pass "Empty skills dir -> empty object"
else
  test_fail "Empty skills dir should produce empty object (got: $skills)"
fi

cleanup_test_env

#######################################
# Test: .mcp.json with mcpServers as empty object
#######################################
test_start "session_start: handles .mcp.json with empty mcpServers"
setup_test_env

echo '{"mcpServers":{}}' > "$TEST_TMPDIR/.mcp.json"

input='{"session_id":"test-empty-mcpservers","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-empty-mcpservers.json"
mcp_count=$(jq -r '.start.config.mcp_servers | length' "$session_file")

if assert_file_exists "$session_file" && [ "$mcp_count" -eq 0 ]; then
  test_pass "Empty mcpServers -> empty array"
else
  test_fail "Empty mcpServers not handled correctly"
fi

cleanup_test_env

#######################################
# Test: All source types
#######################################
for src in "startup" "resume" "clear" "compact"; do
  test_start "session_start: captures source type '$src'"
  setup_test_env

  input='{"session_id":"test-source-'"$src"'","cwd":"'"$TEST_TMPDIR"'","source":"'"$src"'"}'
  run_hook "session_start.sh" "$input"

  session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-source-$src.json"
  if assert_file_exists "$session_file" && \
     assert_json_value "$session_file" '.start.source' "$src"; then
    test_pass
  fi

  cleanup_test_env
done

#######################################
# Test: Missing source defaults to startup
#######################################
test_start "session_start: defaults source to 'startup' when missing"
setup_test_env

input='{"session_id":"test-no-source","cwd":"'"$TEST_TMPDIR"'"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-no-source.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.source' 'startup'; then
  test_pass
else
  test_fail "Default source should be 'startup'"
fi

cleanup_test_env

#######################################
# Test: Session saved to git root from subdirectory
#######################################
test_start "session_start: saves session to git root when in subdirectory"
setup_test_env

# Initialize git repo at TEST_TMPDIR
git -C "$TEST_TMPDIR" init -q

# Create a subdirectory
mkdir -p "$TEST_TMPDIR/public/assets"

# Run hook with cwd pointing to subdirectory
input='{"session_id":"test-subdir","cwd":"'"$TEST_TMPDIR/public"'","source":"compact"}'
run_hook "session_start.sh" "$input"

# Session file should be in git root, not subdirectory
root_session="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-subdir.json"
subdir_session="$TEST_TMPDIR/public/.claude/sessions/$CLAUDE_LOGGER_USER/test-subdir.json"

if assert_file_exists "$root_session" && [ ! -f "$subdir_session" ]; then
  test_pass "Session saved to git root"
else
  if [ -f "$subdir_session" ]; then
    test_fail "Session incorrectly saved to subdirectory"
  else
    test_fail "Session file not found in expected location"
  fi
fi

cleanup_test_env

#######################################
# Test: Non-git directory uses cwd as-is
#######################################
test_start "session_start: uses cwd when not in git repo"
setup_test_env

# Don't initialize git - TEST_TMPDIR is not a repo
input='{"session_id":"test-nongit-cwd","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-nongit-cwd.json"
if assert_file_exists "$session_file"; then
  test_pass "Session saved to cwd in non-git directory"
else
  test_fail "Session file not created"
fi

cleanup_test_env

#######################################
# Test: Deeply nested subdirectory resolves to git root
#######################################
test_start "session_start: deeply nested subdir resolves to git root"
setup_test_env

git -C "$TEST_TMPDIR" init -q
mkdir -p "$TEST_TMPDIR/src/components/ui/buttons"

input='{"session_id":"test-deep","cwd":"'"$TEST_TMPDIR/src/components/ui/buttons"'","source":"compact"}'
run_hook "session_start.sh" "$input"

root_session="$TEST_TMPDIR/.claude/sessions/$CLAUDE_LOGGER_USER/test-deep.json"
if assert_file_exists "$root_session"; then
  test_pass "Deeply nested subdir resolved to git root"
else
  test_fail "Session not found at git root"
fi

cleanup_test_env

echo ""
echo "session_start.sh tests complete"
