#!/usr/bin/env bash
#
# Tests for install.sh --global flag
#
# Usage: bash tests/test_global_install.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMPDIR=""
MOCK_HOME=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#######################################
# Test helpers
#######################################

setup_test() {
  TEST_TMPDIR=$(mktemp -d)
  MOCK_HOME="$TEST_TMPDIR/home"
  mkdir -p "$MOCK_HOME"
  mkdir -p "$TEST_TMPDIR/project"
}

cleanup_test() {
  if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

test_start() {
  echo -n "Testing: $1... "
  TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
  echo -e "${GREEN}PASS${NC}"
  [ -n "${1:-}" ] && echo "  $1" || true
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
  echo -e "${RED}FAIL${NC}"
  echo "  $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Run install.sh --global with mocked HOME
# Global mode no longer requires username input
run_global_install() {
  HOME="$MOCK_HOME" bash "$REPO_DIR/install.sh" --global 2>&1
}

# Run install.sh for project (existing behavior)
run_project_install() {
  local project_dir="$1"
  local nickname="$2"
  echo "$nickname" | bash "$REPO_DIR/install.sh" "$project_dir" 2>&1
}

#######################################
# Test: --global installs hooks to ~/.claude/hooks/
#######################################
test_start "--global installs hooks to ~/.claude/hooks/"
setup_test

output=$(run_global_install "testuser")

if [ -f "$MOCK_HOME/.claude/hooks/session_start.sh" ] && \
   [ -f "$MOCK_HOME/.claude/hooks/session_end.sh" ]; then
  if [ -x "$MOCK_HOME/.claude/hooks/session_start.sh" ] && \
     [ -x "$MOCK_HOME/.claude/hooks/session_end.sh" ]; then
    test_pass "hooks installed and executable"
  else
    test_fail "hooks not executable"
  fi
else
  test_fail "hooks not installed to ~/.claude/hooks/"
fi

cleanup_test

#######################################
# Test: --global creates ~/.claude/settings.json
#######################################
test_start "--global creates ~/.claude/settings.json"
setup_test

run_global_install "testuser" > /dev/null

if [ -f "$MOCK_HOME/.claude/settings.json" ]; then
  if jq -e '.hooks.SessionStart' "$MOCK_HOME/.claude/settings.json" > /dev/null 2>&1; then
    test_pass
  else
    test_fail "settings.json missing SessionStart hook"
  fi
else
  test_fail "settings.json not created"
fi

cleanup_test

#######################################
# Test: --global creates global-mode marker
#######################################
test_start "--global creates ~/.claude-logger/global-mode marker"
setup_test

run_global_install "testuser" > /dev/null

if [ -f "$MOCK_HOME/.claude-logger/global-mode" ]; then
  test_pass
else
  test_fail "global-mode marker not created"
fi

cleanup_test

#######################################
# Test: --global settings use absolute paths
#######################################
test_start "--global settings use absolute paths for hooks"
setup_test

run_global_install "testuser" > /dev/null

hook_cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$MOCK_HOME/.claude/settings.json" 2>/dev/null || echo "")

if echo "$hook_cmd" | grep -q "^/"; then
  test_pass "hook command is absolute path: $hook_cmd"
else
  test_fail "hook command not absolute: $hook_cmd"
fi

cleanup_test

#######################################
# Test: --global skips gitignore check
#######################################
test_start "--global skips gitignore warning"
setup_test

# Create a .gitignore in mock home (shouldn't matter)
echo ".claude/" > "$MOCK_HOME/.gitignore"

output=$(run_global_install "testuser")

if echo "$output" | grep -q "WARNING.*Critical files"; then
  test_fail "gitignore warning shown in global mode"
else
  test_pass
fi

cleanup_test

#######################################
# Test: --global reinstall doesn't duplicate hooks
#######################################
test_start "--global reinstall doesn't duplicate hooks"
setup_test

run_global_install "testuser" > /dev/null
start_count_before=$(jq '.hooks.SessionStart | length' "$MOCK_HOME/.claude/settings.json")

run_global_install "testuser" > /dev/null
start_count_after=$(jq '.hooks.SessionStart | length' "$MOCK_HOME/.claude/settings.json")

if [ "$start_count_before" = "$start_count_after" ]; then
  test_pass
else
  test_fail "hooks duplicated: before=$start_count_before after=$start_count_after"
fi

cleanup_test

#######################################
# Test: --global success message shows org/repo path format
#######################################
test_start "--global success message shows org/repo session path"
setup_test

output=$(run_global_install)

if echo "$output" | grep -q "~/.claude-logger/sessions/{org}/{repo}/"; then
  test_pass
else
  test_fail "success message doesn't show org/repo path format"
  echo "Output was: $output"
fi

cleanup_test

#######################################
# Test: Project install still works (no --global)
#######################################
test_start "project install still works without --global"
setup_test

run_project_install "$TEST_TMPDIR/project" "testuser" > /dev/null

if [ -f "$TEST_TMPDIR/project/.claude/hooks/session_start.sh" ] && \
   [ -f "$TEST_TMPDIR/project/.claude/settings.json" ]; then
  # Ensure no global-mode marker created
  if [ ! -f "$MOCK_HOME/.claude-logger/global-mode" ]; then
    test_pass
  else
    test_fail "global-mode marker created for project install"
  fi
else
  test_fail "project install failed"
fi

cleanup_test

#######################################
# Test: Hook uses global storage when marker exists (with git remote)
#######################################
test_start "hook stores sessions globally by org/repo when marker exists"
setup_test

# Install globally
run_global_install > /dev/null

# Create a test project directory with git remote
mkdir -p "$TEST_TMPDIR/project"
git -C "$TEST_TMPDIR/project" init -q
git -C "$TEST_TMPDIR/project" remote add origin "git@github.com:test-org/test-repo.git"

# Run session_start hook with mocked HOME
SESSION_ID="test-session-global-$(date +%s)"
HOOK_INPUT=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$TEST_TMPDIR/project",
  "transcript_path": "/tmp/transcript.jsonl"
}
EOF
)

echo "$HOOK_INPUT" | HOME="$MOCK_HOME" bash "$MOCK_HOME/.claude/hooks/session_start.sh" 2>/dev/null

# Check session was created in global location organized by org/repo
if [ -f "$MOCK_HOME/.claude-logger/sessions/test-org/test-repo/$SESSION_ID.json" ]; then
  test_pass "session stored at org/repo path"
else
  # Check if it was created in project (wrong)
  if find "$TEST_TMPDIR/project/.claude/sessions" -name "$SESSION_ID.json" 2>/dev/null | grep -q .; then
    test_fail "session created in project instead of global"
  else
    # Check if it's somewhere else in global
    found_path=$(find "$MOCK_HOME/.claude-logger/sessions" -name "$SESSION_ID.json" 2>/dev/null | head -1)
    if [ -n "$found_path" ]; then
      test_fail "session created at wrong path: $found_path"
    else
      test_fail "session file not created anywhere"
    fi
  fi
fi

cleanup_test

#######################################
# Test: Hook uses project storage when marker absent
#######################################
test_start "hook stores sessions in project when marker absent"
setup_test

# Install to project (no global marker)
run_project_install "$TEST_TMPDIR/project" "testuser" > /dev/null

# Run session_start hook
SESSION_ID="test-session-project-$(date +%s)"
HOOK_INPUT=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$TEST_TMPDIR/project",
  "transcript_path": "/tmp/transcript.jsonl"
}
EOF
)

echo "$HOOK_INPUT" | HOME="$MOCK_HOME" CLAUDE_LOGGER_USER="testuser" bash "$TEST_TMPDIR/project/.claude/hooks/session_start.sh" 2>/dev/null

# Check session was created in project location
if [ -f "$TEST_TMPDIR/project/.claude/sessions/testuser/$SESSION_ID.json" ]; then
  test_pass
else
  test_fail "session file not created in project"
fi

cleanup_test

#######################################
# Test: Session end hook respects global mode
#######################################
test_start "session_end respects global mode"
setup_test

# Install globally
run_global_install > /dev/null

# Create project with git remote
mkdir -p "$TEST_TMPDIR/project"
git -C "$TEST_TMPDIR/project" init -q
git -C "$TEST_TMPDIR/project" remote add origin "git@github.com:end-org/end-repo.git"

# Create session via start hook
SESSION_ID="test-session-end-$(date +%s)"
START_INPUT=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$TEST_TMPDIR/project",
  "transcript_path": "/tmp/transcript.jsonl"
}
EOF
)

echo "$START_INPUT" | HOME="$MOCK_HOME" bash "$MOCK_HOME/.claude/hooks/session_start.sh" 2>/dev/null

# Run session_end hook
END_INPUT=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$TEST_TMPDIR/project",
  "reason": "logout"
}
EOF
)

echo "$END_INPUT" | HOME="$MOCK_HOME" bash "$MOCK_HOME/.claude/hooks/session_end.sh" 2>/dev/null

# Check session was completed
SESSION_FILE="$MOCK_HOME/.claude-logger/sessions/end-org/end-repo/$SESSION_ID.json"
if [ -f "$SESSION_FILE" ]; then
  status=$(jq -r '.status' "$SESSION_FILE")
  if [ "$status" = "complete" ]; then
    test_pass
  else
    test_fail "session status is '$status', expected 'complete'"
  fi
else
  test_fail "session file not found at global path"
fi

cleanup_test

#######################################
# Test: Global sessions capture project context and org/repo
#######################################
test_start "global sessions capture project cwd, git info, and org/repo"
setup_test

# Install globally
run_global_install > /dev/null

# Create a git repo in project with remote
mkdir -p "$TEST_TMPDIR/project"
git -C "$TEST_TMPDIR/project" init -q
git -C "$TEST_TMPDIR/project" config user.email "test@test.com"
git -C "$TEST_TMPDIR/project" config user.name "Test"
git -C "$TEST_TMPDIR/project" remote add origin "https://github.com/context-org/context-repo.git"
echo "test" > "$TEST_TMPDIR/project/file.txt"
git -C "$TEST_TMPDIR/project" add .
git -C "$TEST_TMPDIR/project" commit -q -m "initial"

# Run session_start hook
SESSION_ID="test-session-context-$(date +%s)"
HOOK_INPUT=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$TEST_TMPDIR/project",
  "transcript_path": "/tmp/transcript.jsonl"
}
EOF
)

echo "$HOOK_INPUT" | HOME="$MOCK_HOME" bash "$MOCK_HOME/.claude/hooks/session_start.sh" 2>/dev/null

# Check session captures project context including org/repo
SESSION_FILE="$MOCK_HOME/.claude-logger/sessions/context-org/context-repo/$SESSION_ID.json"
if [ -f "$SESSION_FILE" ]; then
  cwd=$(jq -r '.start.cwd' "$SESSION_FILE")
  is_repo=$(jq -r '.start.git.is_repo' "$SESSION_FILE")
  org=$(jq -r '.start.git.org' "$SESSION_FILE")
  repo=$(jq -r '.start.git.repo' "$SESSION_FILE")

  if [ "$cwd" = "$TEST_TMPDIR/project" ] && [ "$is_repo" = "true" ] && \
     [ "$org" = "context-org" ] && [ "$repo" = "context-repo" ]; then
    test_pass "cwd=$cwd, is_repo=$is_repo, org=$org, repo=$repo"
  else
    test_fail "cwd=$cwd, is_repo=$is_repo, org=$org, repo=$repo"
  fi
else
  test_fail "session file not found at expected path"
fi

cleanup_test

#######################################
# Test: Project-installed hooks respect global-mode marker
# This tests hooks installed via `./install.sh /path/to/project`
# when a global-mode marker exists from a previous global install
#######################################
test_start "project-installed hooks respect global-mode marker"
setup_test

# First, do a global install to create the marker
run_global_install > /dev/null

# Then, install to a project directory (simulating outdated hooks scenario)
mkdir -p "$TEST_TMPDIR/project"
git -C "$TEST_TMPDIR/project" init -q
git -C "$TEST_TMPDIR/project" remote add origin "git@github.com:respect-org/respect-repo.git"
run_project_install "$TEST_TMPDIR/project" "testuser" > /dev/null

# The global-mode marker should still exist
if [ ! -f "$MOCK_HOME/.claude-logger/global-mode" ]; then
  test_fail "global-mode marker was removed by project install"
  cleanup_test
else
  # Run the PROJECT hooks (not global) with global-mode marker present
  SESSION_ID="test-project-respects-global-$(date +%s)"
  HOOK_INPUT=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$TEST_TMPDIR/project",
  "transcript_path": "/tmp/transcript.jsonl"
}
EOF
)

  echo "$HOOK_INPUT" | HOME="$MOCK_HOME" bash "$TEST_TMPDIR/project/.claude/hooks/session_start.sh" 2>/dev/null

  # Check session was created in GLOBAL location by org/repo (because marker exists)
  if [ -f "$MOCK_HOME/.claude-logger/sessions/respect-org/respect-repo/$SESSION_ID.json" ]; then
    test_pass "project hooks correctly routed to global storage by org/repo"
  else
    # Check if it was created in project (wrong - should respect global marker)
    if find "$TEST_TMPDIR/project/.claude/sessions" -name "$SESSION_ID.json" 2>/dev/null | grep -q .; then
      test_fail "project hooks ignored global-mode marker - stored in project instead"
    else
      found_path=$(find "$MOCK_HOME/.claude-logger/sessions" -name "$SESSION_ID.json" 2>/dev/null | head -1)
      if [ -n "$found_path" ]; then
        test_fail "session created at wrong path: $found_path"
      else
        test_fail "session file not created anywhere"
      fi
    fi
  fi
fi

cleanup_test

#######################################
# Test: Global mode falls back to _local for repos without remote
#######################################
test_start "global mode uses _local/{dirname} for repos without remote"
setup_test

# Install globally
run_global_install > /dev/null

# Create a git repo WITHOUT remote
mkdir -p "$TEST_TMPDIR/my-local-project"
git -C "$TEST_TMPDIR/my-local-project" init -q

# Run session_start hook
SESSION_ID="test-session-local-$(date +%s)"
HOOK_INPUT=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$TEST_TMPDIR/my-local-project",
  "transcript_path": "/tmp/transcript.jsonl"
}
EOF
)

echo "$HOOK_INPUT" | HOME="$MOCK_HOME" bash "$MOCK_HOME/.claude/hooks/session_start.sh" 2>/dev/null

# Check session was created in _local/dirname path
if [ -f "$MOCK_HOME/.claude-logger/sessions/_local/my-local-project/$SESSION_ID.json" ]; then
  # Also verify org/repo in metadata
  org=$(jq -r '.start.git.org' "$MOCK_HOME/.claude-logger/sessions/_local/my-local-project/$SESSION_ID.json")
  repo=$(jq -r '.start.git.repo' "$MOCK_HOME/.claude-logger/sessions/_local/my-local-project/$SESSION_ID.json")
  if [ "$org" = "_local" ] && [ "$repo" = "my-local-project" ]; then
    test_pass "session at _local/my-local-project with correct metadata"
  else
    test_fail "metadata wrong: org=$org, repo=$repo"
  fi
else
  found_path=$(find "$MOCK_HOME/.claude-logger/sessions" -name "$SESSION_ID.json" 2>/dev/null | head -1)
  if [ -n "$found_path" ]; then
    test_fail "session created at wrong path: $found_path"
  else
    test_fail "session file not created anywhere"
  fi
fi

cleanup_test

#######################################
# Test: Global mode doesn't require CLAUDE_LOGGER_USER
#######################################
test_start "global mode works without CLAUDE_LOGGER_USER env var"
setup_test

# Install globally
run_global_install > /dev/null

# Create a project with remote
mkdir -p "$TEST_TMPDIR/project"
git -C "$TEST_TMPDIR/project" init -q
git -C "$TEST_TMPDIR/project" remote add origin "git@github.com:no-user-org/no-user-repo.git"

# Run session_start hook WITHOUT setting CLAUDE_LOGGER_USER
SESSION_ID="test-session-no-user-$(date +%s)"
HOOK_INPUT=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "cwd": "$TEST_TMPDIR/project",
  "transcript_path": "/tmp/transcript.jsonl"
}
EOF
)

# Explicitly unset CLAUDE_LOGGER_USER
unset CLAUDE_LOGGER_USER
echo "$HOOK_INPUT" | HOME="$MOCK_HOME" bash "$MOCK_HOME/.claude/hooks/session_start.sh" 2>/dev/null

# Check session was created (should work without username in global mode)
if [ -f "$MOCK_HOME/.claude-logger/sessions/no-user-org/no-user-repo/$SESSION_ID.json" ]; then
  test_pass "session created without CLAUDE_LOGGER_USER"
else
  test_fail "session not created without CLAUDE_LOGGER_USER"
fi

cleanup_test

#######################################
# Summary
#######################################
echo ""
echo "========================================"
echo -e "Tests: $TESTS_RUN | ${GREEN}Passed: $TESTS_PASSED${NC} | ${RED}Failed: $TESTS_FAILED${NC}"
echo "========================================"

if [ $TESTS_FAILED -gt 0 ]; then
  exit 1
fi
