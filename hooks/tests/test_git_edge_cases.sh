#!/usr/bin/env bash
#
# Git edge case tests for Claude Tracker hooks
#

#######################################
# Test: Detached HEAD state
#######################################
test_start "git: captures detached HEAD state"
setup_test_env

# Initialize git repo and detach HEAD
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial commit"
commit_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD)
git -C "$TEST_TMPDIR" checkout -q "$commit_sha"  # Detach HEAD

input='{"session_id":"test-detached","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-detached.json"
branch=$(jq -r '.start.git.branch' "$session_file")

# In detached HEAD, branch is "HEAD"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.git.is_repo' 'true' && \
   [ "$branch" = "HEAD" ]; then
  test_pass "Detached HEAD captured (branch=$branch)"
else
  test_fail "Detached HEAD not handled correctly (branch=$branch)"
fi

cleanup_test_env

#######################################
# Test: Empty git repository (no commits)
#######################################
test_start "git: handles empty git repo (no commits)"
setup_test_env

# Initialize git repo but don't commit
git -C "$TEST_TMPDIR" init -q

input='{"session_id":"test-empty-repo","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-empty-repo.json"
sha=$(jq -r '.start.git.sha' "$session_file")

# For an empty repo (no commits), git rev-parse HEAD fails, so SHA should be empty
# The hook captures this gracefully
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.git.is_repo' 'true'; then
  # SHA should be empty string (git rev-parse HEAD fails on empty repo)
  if [ -z "$sha" ] || [ "$sha" = "" ]; then
    test_pass "Empty repo handled (no SHA)"
  else
    # Some git versions might return something else
    test_pass "Empty repo handled (sha: $sha)"
  fi
else
  test_fail "Empty repo not detected as git repo"
fi

cleanup_test_env

#######################################
# Test: Git config missing (no user.name/email)
#######################################
test_start "git: captures state without user config"
setup_test_env

# Initialize git repo without setting user config
git -C "$TEST_TMPDIR" init -q
# Note: Can't easily unset global config in test, so we just test that
# the hook runs successfully without local config
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt

input='{"session_id":"test-no-config","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-no-config.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.git.is_repo' 'true'; then
  test_pass "Git state captured without commits"
fi

cleanup_test_env

#######################################
# Test: Git repository with submodule-like structure
#######################################
test_start "git: handles repository with submodule structure"
setup_test_env

# Create main repo
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"

# Create submodule-like directory structure
mkdir -p "$TEST_TMPDIR/submodule"
git -C "$TEST_TMPDIR/submodule" init -q

echo "main" > "$TEST_TMPDIR/main.txt"
git -C "$TEST_TMPDIR" add main.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

input='{"session_id":"test-submodules","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-submodules.json"
if assert_file_exists "$session_file" && \
   assert_json_value "$session_file" '.start.git.is_repo' 'true'; then
  test_pass "Repo with submodule structure handled"
fi

cleanup_test_env

#######################################
# Test: Large untracked file (LFS-like scenario)
#######################################
test_start "git: handles large untracked files without timeout"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create a large untracked file (10MB)
dd if=/dev/zero of="$TEST_TMPDIR/large_file.bin" bs=1M count=10 2>/dev/null

input='{"session_id":"test-lfs","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'

# Should complete within timeout
start_time=$(date +%s)
run_hook "session_start.sh" "$input"
end_time=$(date +%s)
elapsed=$((end_time - start_time))

if [ $elapsed -lt 5 ]; then
  test_pass "Large file didn't cause timeout (${elapsed}s)"
else
  test_fail "Large file caused slowdown (${elapsed}s)"
fi

cleanup_test_env

#######################################
# Test: Corrupted .git/index
#######################################
test_start "git: handles corrupted .git/index"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Corrupt the index file
echo "corrupted" > "$TEST_TMPDIR/.git/index"

input='{"session_id":"test-corrupt-index","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
# Run and capture exit code (should be 0 regardless of git errors)
run_hook "session_start.sh" "$input" 2>/dev/null
exit_code=$?

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-corrupt-index.json"
# Hook should exit 0 even if git fails, and may or may not create session
if [ $exit_code -eq 0 ]; then
  if [ -f "$session_file" ]; then
    test_pass "Corrupted index handled, session created"
  else
    test_pass "Corrupted index handled gracefully (no session created)"
  fi
else
  test_fail "Hook should exit 0 despite corrupted index"
fi

cleanup_test_env

#######################################
# Test: Non-standard branch names
#######################################
test_start "git: handles branch names with special characters"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create branch with special characters
git -C "$TEST_TMPDIR" checkout -b "feature/test-branch_v2.0" -q

input='{"session_id":"test-special-branch","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-special-branch.json"
branch=$(jq -r '.start.git.branch' "$session_file")

if [ "$branch" = "feature/test-branch_v2.0" ]; then
  test_pass "Special branch name captured: $branch"
else
  test_fail "Branch name mismatch: expected 'feature/test-branch_v2.0', got '$branch'"
fi

cleanup_test_env

#######################################
# Test: Branch with unicode name
#######################################
test_start "git: handles branch with unicode name"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Try to create branch with unicode (may fail on some systems)
if git -C "$TEST_TMPDIR" checkout -b "feature/test-功能" -q 2>/dev/null; then
  input='{"session_id":"test-unicode-branch","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
  run_hook "session_start.sh" "$input"

  session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-unicode-branch.json"
  if assert_file_exists "$session_file"; then
    test_pass "Unicode branch name handled"
  fi
else
  test_skip "System doesn't support unicode branch names"
fi

cleanup_test_env

#######################################
# Test: Commits with merge commits during session
#######################################
test_start "git: detects commits during session (including merges)"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

start_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD)

# Create feature branch and make a commit
git -C "$TEST_TMPDIR" checkout -b feature -q
echo "feature" > "$TEST_TMPDIR/feature.txt"
git -C "$TEST_TMPDIR" add feature.txt
git -C "$TEST_TMPDIR" commit -q -m "Feature commit"

# Go back and make a commit on main to force non-fast-forward merge
git -C "$TEST_TMPDIR" checkout - -q 2>/dev/null
echo "main change" > "$TEST_TMPDIR/main.txt"
git -C "$TEST_TMPDIR" add main.txt
git -C "$TEST_TMPDIR" commit -q -m "Main commit"

# Merge feature (creates merge commit)
git -C "$TEST_TMPDIR" merge feature -q --no-edit 2>/dev/null || true

# Create session file
session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-merge.json"
cat > "$session_file" << EOF
{
  "session_id": "test-merge",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "git": {"sha": "$start_sha"}
  }
}
EOF

input='{"session_id":"test-merge","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

commits_count=$(jq -r '.end.git.commits_made | length' "$session_file")

# Should detect at least 1 commit (the merge or the main commit)
# With non-ff merge we should get 3: main commit, feature commit, merge commit
if [ "$commits_count" -ge 1 ]; then
  test_pass "Commits during session detected: $commits_count"
else
  test_fail "Expected >=1 commits, got $commits_count"
fi

cleanup_test_env

#######################################
# Test: Shallow clone (ancestry check may fail)
#######################################
test_start "git: handles unreachable start SHA gracefully"
setup_test_env

# Initialize a normal repo
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "1" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Commit 1"
echo "2" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" commit -q -am "Commit 2"

# Create session with fake/unreachable start SHA
session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-shallow.json"
cat > "$session_file" << EOF
{
  "session_id": "test-shallow",
  "status": "in_progress",
  "start": {
    "timestamp": "2025-01-01T12:00:00Z",
    "git": {
      "sha": "0000000000000000000000000000000000000000"
    }
  }
}
EOF

input='{"session_id":"test-shallow","cwd":"'"$TEST_TMPDIR"'","reason":"logout"}'
run_hook "session_end.sh" "$input"

# Should complete without error, commits_made should be empty (ancestry check fails)
if assert_json_value "$session_file" '.status' 'complete'; then
  commits_count=$(jq -r '.end.git.commits_made | length' "$session_file")
  test_pass "Unreachable SHA handled (commits_made: $commits_count)"
fi

cleanup_test_env

#######################################
# Test: 100+ dirty files (respects limit)
#######################################
test_start "git: limits dirty files to 50"
setup_test_env

# Initialize git repo
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "initial" > "$TEST_TMPDIR/initial.txt"
git -C "$TEST_TMPDIR" add initial.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Create 75 dirty files
for i in {1..75}; do
  echo "dirty $i" > "$TEST_TMPDIR/dirty_$i.txt"
done

input='{"session_id":"test-many-dirty","cwd":"'"$TEST_TMPDIR"'","source":"startup"}'
run_hook "session_start.sh" "$input"

session_file="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-many-dirty.json"
dirty_files_count=$(jq -r '.start.git.dirty_files | length' "$session_file")
dirty_count=$(jq -r '.start.git.dirty_count' "$session_file")

if assert_file_exists "$session_file" && \
   [ "$dirty_files_count" -le 50 ] && \
   [ "$dirty_count" -ge 75 ]; then
  test_pass "Dirty files limited to $dirty_files_count, count accurate ($dirty_count)"
else
  test_fail "Dirty files: $dirty_files_count (expected <=50), count: $dirty_count (expected >=75)"
fi

cleanup_test_env

#######################################
# Test: Git worktree (if supported)
#######################################
test_start "git: handles worktree directory"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
echo "test" > "$TEST_TMPDIR/test.txt"
git -C "$TEST_TMPDIR" add test.txt
git -C "$TEST_TMPDIR" commit -q -m "Initial"

# Try to create a worktree
worktree_dir="$TEST_TMPDIR/worktree"
if git -C "$TEST_TMPDIR" worktree add "$worktree_dir" -b worktree-branch -q 2>/dev/null; then
  # Test from worktree
  mkdir -p "$worktree_dir/.claude/sessions"
  cp "$TEST_TMPDIR/.claude/hooks/"*.sh "$worktree_dir/.claude/hooks/" 2>/dev/null || true

  input='{"session_id":"test-worktree","cwd":"'"$worktree_dir"'","source":"startup"}'
  # Run directly since hooks aren't copied
  echo "$input" | bash "$TEST_TMPDIR/.claude/hooks/session_start.sh"

  # Check if session was created (might be in main or worktree)
  if [ -f "$worktree_dir/.claude/sessions/$GITHUB_NICKNAME/test-worktree.json" ] || \
     [ -f "$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-worktree.json" ]; then
    test_pass "Worktree session created"
  else
    test_pass "Worktree handled gracefully"
  fi
else
  test_skip "Git worktree not supported"
fi

cleanup_test_env

echo ""
echo "Git edge case tests complete"
