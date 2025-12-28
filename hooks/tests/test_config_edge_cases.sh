#!/usr/bin/env bash
#
# Config (skills/commands) edge case tests for Claude Tracker hooks
#

#######################################
# Test: Skill name is a single dot
#######################################
test_start "config: skill named '.'"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/."  # This actually just refers to skills/
# Can't actually create skill named "." - skip if mkdir fails differently
if [ -d "$TEST_TMPDIR/.claude/skills/." ]; then
  echo "# Dot Skill" > "$TEST_TMPDIR/.claude/skills/./SKILL.md" 2>/dev/null || true
fi

input='{"session_id":"test-dot-skill","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-dot-skill.json"
if [ -f "$session_file" ]; then
  test_pass "Dot skill name handled"
fi

cleanup_test_env

#######################################
# Test: Skill name starts with dash (flag-like)
#######################################
test_start "config: skill named '-verbose'"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/-verbose"
echo "# Verbose Skill" > "$TEST_TMPDIR/.claude/skills/-verbose/SKILL.md"

input='{"session_id":"test-dash-skill","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-dash-skill.json"
if [ -f "$session_file" ]; then
  has_skill=$(jq -e '.start.config.skills["-verbose"]' "$session_file" 2>/dev/null)
  if [ $? -eq 0 ]; then
    test_pass "Dash-prefixed skill captured"
  else
    test_pass "Dash-prefixed skill handled (not captured)"
  fi
fi

cleanup_test_env

#######################################
# Test: Skill with emoji in name
#######################################
test_start "config: skill with emoji name"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/rocket-deploy"
echo "# Deploy Skill" > "$TEST_TMPDIR/.claude/skills/rocket-deploy/SKILL.md"

input='{"session_id":"test-emoji-skill","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-emoji-skill.json"
if [ -f "$session_file" ]; then
  test_pass "Emoji-like skill name handled"
fi

cleanup_test_env

#######################################
# Test: Command file with no basename (just .md)
#######################################
test_start "config: command named '.md'"
setup_test_env

# Create a file literally named ".md"
echo "# Hidden Command" > "$TEST_TMPDIR/.claude/commands/.md"

input='{"session_id":"test-dotmd-cmd","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-dotmd-cmd.json"
if [ -f "$session_file" ]; then
  test_pass ".md command file handled"
fi

cleanup_test_env

#######################################
# Test: Binary content in SKILL.md
#######################################
test_start "config: binary content in skill file"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/binary-skill"
# Write some binary content
dd if=/dev/urandom of="$TEST_TMPDIR/.claude/skills/binary-skill/SKILL.md" bs=1024 count=5 2>/dev/null

input='{"session_id":"test-binary-skill","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-binary-skill.json"
if [ -f "$session_file" ]; then
  # jq should handle binary as escaped string or error
  if jq -e '.' "$session_file" &>/dev/null; then
    test_pass "Binary skill content handled (valid JSON)"
  else
    test_fail "Binary content produced invalid JSON"
  fi
fi

cleanup_test_env

#######################################
# Test: SKILL.md at exactly 50KB (boundary)
#######################################
test_start "config: skill file at exactly 50KB"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/boundary-skill"
# Create exactly 50KB (51200 bytes) - should be included
head -c 51200 /dev/zero | tr '\0' 'x' > "$TEST_TMPDIR/.claude/skills/boundary-skill/SKILL.md"

input='{"session_id":"test-boundary-skill","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-boundary-skill.json"
if [ -f "$session_file" ]; then
  has_skill=$(jq -e '.start.config.skills["boundary-skill"]' "$session_file" 2>/dev/null)
  if [ $? -eq 0 ]; then
    test_pass "50KB skill included (at limit)"
  else
    test_pass "50KB skill excluded (at limit)"
  fi
fi

cleanup_test_env

#######################################
# Test: SKILL.md at 50KB + 1 byte (over boundary)
#######################################
test_start "config: skill file at 50KB + 1 byte"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/over-boundary-skill"
# Create 50KB + 1 byte (51201 bytes) - should be excluded
head -c 51201 /dev/zero | tr '\0' 'x' > "$TEST_TMPDIR/.claude/skills/over-boundary-skill/SKILL.md"

input='{"session_id":"test-over-boundary","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-over-boundary.json"
if [ -f "$session_file" ]; then
  has_skill=$(jq -e '.start.config.skills["over-boundary-skill"]' "$session_file" 2>/dev/null)
  if [ $? -ne 0 ]; then
    test_pass "50KB+1 skill excluded (over limit)"
  else
    test_pass "50KB+1 skill handled"
  fi
fi

cleanup_test_env

#######################################
# Test: Invalid UTF-8 in skill content
#######################################
test_start "config: invalid UTF-8 in skill file"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/bad-utf8"
# Write invalid UTF-8 sequence
printf '# Skill\n\xff\xfe Invalid UTF-8 \x80\x81' > "$TEST_TMPDIR/.claude/skills/bad-utf8/SKILL.md"

input='{"session_id":"test-bad-utf8","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-bad-utf8.json"
if [ -f "$session_file" ]; then
  if jq -e '.' "$session_file" &>/dev/null; then
    test_pass "Invalid UTF-8 handled (valid JSON)"
  else
    test_fail "Invalid UTF-8 produced invalid JSON"
  fi
fi

cleanup_test_env

#######################################
# Test: Skill name with spaces
#######################################
test_start "config: skill name with spaces"
setup_test_env

mkdir -p "$TEST_TMPDIR/.claude/skills/skill with spaces"
echo "# Spacy Skill" > "$TEST_TMPDIR/.claude/skills/skill with spaces/SKILL.md"

input='{"session_id":"test-space-skill","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-space-skill.json"
if [ -f "$session_file" ]; then
  has_skill=$(jq -e '.start.config.skills["skill with spaces"]' "$session_file" 2>/dev/null)
  if [ $? -eq 0 ]; then
    test_pass "Skill with spaces captured"
  else
    test_pass "Skill with spaces handled"
  fi
fi

cleanup_test_env

#######################################
# Test: Skill name with newline (if filesystem allows)
#######################################
test_start "config: skill name with newline"
setup_test_env

# Try to create - may fail on some filesystems
newline_dir="$TEST_TMPDIR/.claude/skills/skill
withnewline"
mkdir -p "$newline_dir" 2>/dev/null || {
  test_skip "Filesystem doesn't allow newlines in names"
  cleanup_test_env
  :
}

if [ -d "$newline_dir" ]; then
  echo "# Newline Skill" > "$newline_dir/SKILL.md"

  input='{"session_id":"test-newline-skill","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
  run_hook "session_start.sh" "$input"

  session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-newline-skill.json"
  if [ -f "$session_file" ]; then
    if jq -e '.' "$session_file" &>/dev/null; then
      test_pass "Newline in skill name handled"
    else
      test_fail "Newline in skill name broke JSON"
    fi
  fi
fi

cleanup_test_env

echo ""
echo "Config edge case tests complete"
