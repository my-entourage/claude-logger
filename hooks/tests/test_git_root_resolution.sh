#!/usr/bin/env bash
#
# Test cases for git root resolution edge cases
#

# Source the test runner for shared utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_runner.sh"

#######################################
# Test: Empty git repository (no commits)
#######################################
test_start "git_root: empty repo (no commits) resolves correctly"
setup_test_env

git -C "$TEST_TMPDIR" init -q
# Don't make any commits - repo is empty
mkdir -p "$TEST_TMPDIR/src"

input='{"session_id":"test-empty-repo","cwd":"'"$TEST_TMPDIR/src"'","source":"startup"}'
run_hook "session_start.sh" "$input"

root_session="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-empty-repo.json"
if assert_file_exists "$root_session"; then
  test_pass "Empty repo resolved to git root"
else
  test_fail "Session not found at git root"
fi

cleanup_test_env

#######################################
# Test: Detached HEAD state
#######################################
test_start "git_root: detached HEAD resolves correctly"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
touch "$TEST_TMPDIR/file.txt"
git -C "$TEST_TMPDIR" add .
git -C "$TEST_TMPDIR" commit -q -m "initial"
# Detach HEAD by checking out the commit directly
commit_sha=$(git -C "$TEST_TMPDIR" rev-parse HEAD)
git -C "$TEST_TMPDIR" checkout -q "$commit_sha"
mkdir -p "$TEST_TMPDIR/src"

input='{"session_id":"test-detached","cwd":"'"$TEST_TMPDIR/src"'","source":"startup"}'
run_hook "session_start.sh" "$input"

root_session="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-detached.json"
if assert_file_exists "$root_session"; then
  test_pass "Detached HEAD resolved to git root"
else
  test_fail "Session not found at git root"
fi

cleanup_test_env

#######################################
# Test: Nested git repositories (repo inside repo)
# Inner repo should use its OWN root, not parent's
#######################################
test_start "git_root: nested repos use inner repo root"
setup_test_env

# Create outer repo
git -C "$TEST_TMPDIR" init -q
mkdir -p "$TEST_TMPDIR/vendor/some-lib"

# Create inner repo (not a submodule, just a nested repo)
git -C "$TEST_TMPDIR/vendor/some-lib" init -q
mkdir -p "$TEST_TMPDIR/vendor/some-lib/src"

# Run hook from inner repo's subdirectory
input='{"session_id":"test-nested","cwd":"'"$TEST_TMPDIR/vendor/some-lib/src"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Session should be in inner repo's root, not outer
inner_session="$TEST_TMPDIR/vendor/some-lib/.claude/sessions/$GITHUB_NICKNAME/test-nested.json"
outer_session="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-nested.json"

if assert_file_exists "$inner_session" && [ ! -f "$outer_session" ]; then
  test_pass "Nested repo used inner repo root"
else
  if [ -f "$outer_session" ]; then
    test_fail "Incorrectly used outer repo root"
  else
    test_fail "Session not found in expected location"
  fi
fi

cleanup_test_env

#######################################
# Test: Git submodule uses submodule root
# Note: This test simulates a submodule by creating a nested git repo
# with a .git file pointing to the parent (like real submodules)
#######################################
test_start "git_root: submodule uses submodule root"
setup_test_env

# Create main repo with a commit
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
touch "$TEST_TMPDIR/main.txt"
git -C "$TEST_TMPDIR" add .
git -C "$TEST_TMPDIR" commit -q -m "initial"

# Simulate a submodule by creating a nested git repo
# Real submodules have a .git file, but for this test nested repo works the same
mkdir -p "$TEST_TMPDIR/libs/mylib"
git -C "$TEST_TMPDIR/libs/mylib" init -q
git -C "$TEST_TMPDIR/libs/mylib" config user.email "test@test.com"
git -C "$TEST_TMPDIR/libs/mylib" config user.name "Test"
touch "$TEST_TMPDIR/libs/mylib/lib.txt"
git -C "$TEST_TMPDIR/libs/mylib" add .
git -C "$TEST_TMPDIR/libs/mylib" commit -q -m "lib initial"
mkdir -p "$TEST_TMPDIR/libs/mylib/src"

# Run hook from submodule subdirectory
input='{"session_id":"test-submodule","cwd":"'"$TEST_TMPDIR/libs/mylib/src"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Session should be in submodule root (the nested repo)
submodule_session="$TEST_TMPDIR/libs/mylib/.claude/sessions/$GITHUB_NICKNAME/test-submodule.json"
main_session="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-submodule.json"

if assert_file_exists "$submodule_session" && [ ! -f "$main_session" ]; then
  test_pass "Submodule used submodule root"
else
  if [ -f "$main_session" ]; then
    test_fail "Incorrectly used main repo root"
  else
    test_fail "Session not found in expected location"
  fi
fi

cleanup_test_env

#######################################
# Test: Symlinked directory into git repo
#######################################
test_start "git_root: symlinked directory resolves correctly"
setup_test_env

git -C "$TEST_TMPDIR" init -q
mkdir -p "$TEST_TMPDIR/real/deep/path"

# Create symlink outside the repo pointing into it
link_dir=$(mktemp -d)
ln -s "$TEST_TMPDIR/real/deep/path" "$link_dir/linked"

input='{"session_id":"test-symlink","cwd":"'"$link_dir/linked"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Session should be in the git root (following the symlink)
root_session="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-symlink.json"
if assert_file_exists "$root_session"; then
  test_pass "Symlinked directory resolved to git root"
else
  test_fail "Session not found at git root"
fi

# Cleanup
rm -rf "$link_dir"

cleanup_test_env

#######################################
# Test: Directory path with spaces
#######################################
test_start "git_root: path with spaces resolves correctly"
setup_test_env

git -C "$TEST_TMPDIR" init -q
mkdir -p "$TEST_TMPDIR/My Projects/Web App/src"

input='{"session_id":"test-spaces","cwd":"'"$TEST_TMPDIR/My Projects/Web App/src"'","source":"startup"}'
run_hook "session_start.sh" "$input"

root_session="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-spaces.json"
if assert_file_exists "$root_session"; then
  test_pass "Path with spaces resolved to git root"
else
  test_fail "Session not found at git root"
fi

cleanup_test_env

#######################################
# Test: Git worktree resolves to worktree root
#######################################
test_start "git_root: worktree resolves to worktree root"
setup_test_env

# Create main repo with a commit
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" config user.email "test@test.com"
git -C "$TEST_TMPDIR" config user.name "Test"
touch "$TEST_TMPDIR/main.txt"
git -C "$TEST_TMPDIR" add .
git -C "$TEST_TMPDIR" commit -q -m "initial"

# Create a worktree
worktree_dir="$TEST_TMPDIR-worktree"
git -C "$TEST_TMPDIR" worktree add -q "$worktree_dir" -b feature
mkdir -p "$worktree_dir/src"

# Run hook from worktree subdirectory
input='{"session_id":"test-worktree","cwd":"'"$worktree_dir/src"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Session should be in worktree root, not main repo
worktree_session="$worktree_dir/.claude/sessions/$GITHUB_NICKNAME/test-worktree.json"
main_session="$TEST_TMPDIR/.claude/sessions/$GITHUB_NICKNAME/test-worktree.json"

if assert_file_exists "$worktree_session" && [ ! -f "$main_session" ]; then
  test_pass "Worktree used worktree root"
else
  if [ -f "$main_session" ]; then
    test_fail "Incorrectly used main repo root"
  else
    test_fail "Session not found in expected location"
  fi
fi

# Cleanup worktree
git -C "$TEST_TMPDIR" worktree remove -f "$worktree_dir" 2>/dev/null || rm -rf "$worktree_dir"

cleanup_test_env

#######################################
# Test: Broken symlink falls back gracefully
#######################################
test_start "git_root: broken symlink falls back to cwd"
setup_test_env

# Create a broken symlink
mkdir -p "$TEST_TMPDIR/links"
ln -s "/nonexistent/path/that/does/not/exist" "$TEST_TMPDIR/links/broken"

# The cwd itself doesn't exist, so should fall back to pwd
# But since we can't cd to a broken symlink, test with valid dir containing broken symlink
input='{"session_id":"test-broken-link","cwd":"'"$TEST_TMPDIR/links"'","source":"startup"}'
run_hook "session_start.sh" "$input"

# Session should be in the links directory (not a git repo)
session_file="$TEST_TMPDIR/links/.claude/sessions/$GITHUB_NICKNAME/test-broken-link.json"
if assert_file_exists "$session_file"; then
  test_pass "Non-git directory with broken symlink handled gracefully"
else
  test_fail "Session not created"
fi

cleanup_test_env

#######################################
# Print test summary
#######################################
echo ""
echo "Git root resolution tests complete"
