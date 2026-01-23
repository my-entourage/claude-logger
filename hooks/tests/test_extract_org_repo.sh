#!/usr/bin/env bash
#
# Tests for extract_org_repo function
#

#######################################
# Define extract_org_repo function (same as in session_start.sh)
# We define it here to avoid sourcing the full hook which blocks on stdin
#######################################
extract_org_repo() {
  local dir="$1"
  local git_timeout=3
  local remote_url org repo

  remote_url=$(git -C "$dir" remote get-url origin 2>/dev/null)

  if [ -n "$remote_url" ]; then
    if [[ "$remote_url" =~ git@[^:]+:([^/]+)/([^/]+)(\.git)?$ ]]; then
      org="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]%.git}"
    elif [[ "$remote_url" =~ https?://[^/]+/([^/]+)/([^/]+)(\.git)?$ ]]; then
      org="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]%.git}"
    fi

    if [ -n "$org" ] && [ -n "$repo" ]; then
      echo "$org" "$repo"
      return 0
    fi
  fi

  local dirname
  dirname=$(basename "$dir")
  echo "_local" "$dirname"
}

#######################################
# Test: SSH URL parsing (standard format)
#######################################
test_start "extract_org_repo: parses SSH URL (git@github.com:org/repo.git)"
setup_test_env

# Create a git repo with SSH remote
git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" remote add origin "git@github.com:my-org/my-repo.git"

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

if [ "$org" = "my-org" ] && [ "$repo" = "my-repo" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=my-org, repo=my-repo, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: SSH URL without .git suffix
#######################################
test_start "extract_org_repo: parses SSH URL without .git suffix"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" remote add origin "git@github.com:anthropic/claude"

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

if [ "$org" = "anthropic" ] && [ "$repo" = "claude" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=anthropic, repo=claude, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: HTTPS URL parsing
#######################################
test_start "extract_org_repo: parses HTTPS URL"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" remote add origin "https://github.com/my-entourage/claude-logger.git"

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

if [ "$org" = "my-entourage" ] && [ "$repo" = "claude-logger" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=my-entourage, repo=claude-logger, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: HTTPS URL without .git suffix
#######################################
test_start "extract_org_repo: parses HTTPS URL without .git suffix"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" remote add origin "https://github.com/owner/project"

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

if [ "$org" = "owner" ] && [ "$repo" = "project" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=owner, repo=project, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: HTTP URL (non-HTTPS)
#######################################
test_start "extract_org_repo: parses HTTP URL"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" remote add origin "http://github.com/test-org/test-repo.git"

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

if [ "$org" = "test-org" ] && [ "$repo" = "test-repo" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=test-org, repo=test-repo, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: GitLab SSH URL
#######################################
test_start "extract_org_repo: parses GitLab SSH URL"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" remote add origin "git@gitlab.com:company/project.git"

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

if [ "$org" = "company" ] && [ "$repo" = "project" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=company, repo=project, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: Fallback for no remote (local git repo)
#######################################
test_start "extract_org_repo: falls back to _local for repo without remote"
setup_test_env

# Create a git repo without any remote
git -C "$TEST_TMPDIR" init -q

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

expected_dirname=$(basename "$TEST_TMPDIR")
if [ "$org" = "_local" ] && [ "$repo" = "$expected_dirname" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=_local, repo=$expected_dirname, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: Fallback for non-git directory
#######################################
test_start "extract_org_repo: falls back to _local for non-git directory"
setup_test_env

# Use a subdirectory that's not a git repo
NON_GIT_DIR="$TEST_TMPDIR/my-local-project"
mkdir -p "$NON_GIT_DIR"

read -r org repo <<< "$(extract_org_repo "$NON_GIT_DIR")"

if [ "$org" = "_local" ] && [ "$repo" = "my-local-project" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=_local, repo=my-local-project, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: Org/repo with special characters (dashes, underscores)
#######################################
test_start "extract_org_repo: handles org/repo with dashes and underscores"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" remote add origin "git@github.com:my-org_123/my_repo-456.git"

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

if [ "$org" = "my-org_123" ] && [ "$repo" = "my_repo-456" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=my-org_123, repo=my_repo-456, got org=$org, repo=$repo"
fi

cleanup_test_env

#######################################
# Test: Bitbucket SSH URL format
#######################################
test_start "extract_org_repo: parses Bitbucket SSH URL"
setup_test_env

git -C "$TEST_TMPDIR" init -q
git -C "$TEST_TMPDIR" remote add origin "git@bitbucket.org:workspace/repo-name.git"

read -r org repo <<< "$(extract_org_repo "$TEST_TMPDIR")"

if [ "$org" = "workspace" ] && [ "$repo" = "repo-name" ]; then
  test_pass "org=$org, repo=$repo"
else
  test_fail "Expected org=workspace, repo=repo-name, got org=$org, repo=$repo"
fi

cleanup_test_env
