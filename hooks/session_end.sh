#!/usr/bin/env bash
#
# Claude Tracker - Session End Hook
# Captures final git state and marks session complete.
#
# Design decisions:
# - Same robustness principles as start hook
# - Idempotent: safe to run multiple times
# - Graceful degradation on all failures
#

set -o pipefail

#######################################
# Dependencies check
#######################################
if ! command -v jq &>/dev/null; then
  exit 0
fi

#######################################
# Timeout wrapper (macOS doesn't have timeout by default)
#######################################
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  if command -v timeout &>/dev/null; then
    timeout "$timeout_seconds" "$@"
  else
    # Fallback: run without timeout (accept small risk of hang)
    "$@"
  fi
}

#######################################
# Read and validate input
#######################################
HOOK_INPUT=$(cat)
[ -z "$HOOK_INPUT" ] && exit 0

SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty')
EXIT_REASON=$(echo "$HOOK_INPUT" | jq -r '.reason // "other"')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Fallback for CWD
if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
  CWD=$(pwd)
fi

#######################################
# Locate session file
#######################################
SESSION_FILE="$CWD/.claude/sessions/$SESSION_ID.json"

# Only update if session file exists and is readable
if [ ! -f "$SESSION_FILE" ] || [ ! -r "$SESSION_FILE" ]; then
  exit 0
fi

# Verify it's valid JSON before modifying
if ! jq -e '.' "$SESSION_FILE" &>/dev/null; then
  exit 0
fi

# Don't update if already complete (idempotent)
if jq -e '.status == "complete"' "$SESSION_FILE" &>/dev/null; then
  exit 0
fi

#######################################
# Capture end git state
#######################################
capture_end_git() {
  local git_timeout=3
  local sha="" dirty="false" commits_made="[]"

  if run_with_timeout "$git_timeout" git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
    sha=$(run_with_timeout "$git_timeout" git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")

    # Check if dirty
    if [ -n "$(run_with_timeout "$git_timeout" git -C "$CWD" status --porcelain 2>/dev/null | head -1)" ]; then
      dirty="true"
    fi

    # Find commits made during session
    local start_sha
    start_sha=$(jq -r '.start.git.sha // ""' "$SESSION_FILE")
    if [ -n "$start_sha" ] && [ -n "$sha" ] && [ "$start_sha" != "$sha" ]; then
      # Verify start_sha is an ancestor (handles branch switches)
      if run_with_timeout "$git_timeout" git -C "$CWD" merge-base --is-ancestor "$start_sha" "$sha" 2>/dev/null; then
        commits_made=$(run_with_timeout "$git_timeout" git -C "$CWD" log --format='%H' "$start_sha..$sha" 2>/dev/null | head -100 | jq -R -s 'split("\n") | map(select(length > 0))') || commits_made="[]"
      fi
    fi
  fi

  jq -n \
    --arg sha "$sha" \
    --argjson dirty "$dirty" \
    --argjson commits_made "$commits_made" \
    '{sha: $sha, dirty: $dirty, commits_made: $commits_made}'
}

GIT_END_DATA=$(capture_end_git)

#######################################
# Calculate duration (portable)
#######################################
calculate_duration() {
  local start_ts duration=0

  start_ts=$(jq -r '.start.timestamp // ""' "$SESSION_FILE")
  [ -z "$start_ts" ] && echo "0" && return

  local start_epoch end_epoch

  # Try GNU date first (Linux), then BSD date (macOS)
  if date --version &>/dev/null 2>&1; then
    # GNU date
    start_epoch=$(date -d "$start_ts" "+%s" 2>/dev/null) || start_epoch=0
    end_epoch=$(date -d "$TIMESTAMP" "+%s" 2>/dev/null) || end_epoch=0
  else
    # BSD date (macOS)
    start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_ts" "+%s" 2>/dev/null) || start_epoch=0
    end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$TIMESTAMP" "+%s" 2>/dev/null) || end_epoch=0
  fi

  if [ "$start_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ] && [ "$end_epoch" -ge "$start_epoch" ]; then
    duration=$((end_epoch - start_epoch))
  fi

  echo "$duration"
}

DURATION=$(calculate_duration)

#######################################
# Update session file (atomic)
#######################################
TMP_FILE="$SESSION_FILE.tmp.$$"

jq \
  --arg timestamp "$TIMESTAMP" \
  --arg reason "$EXIT_REASON" \
  --argjson duration "$DURATION" \
  --argjson git "$GIT_END_DATA" \
  '.status = "complete" | .end = {
    timestamp: $timestamp,
    reason: $reason,
    duration_seconds: $duration,
    git: $git
  }' "$SESSION_FILE" > "$TMP_FILE" 2>/dev/null

# Atomic move (only if write succeeded and produced valid JSON)
if [ -s "$TMP_FILE" ] && jq -e '.' "$TMP_FILE" &>/dev/null; then
  mv "$TMP_FILE" "$SESSION_FILE" 2>/dev/null
else
  rm -f "$TMP_FILE" 2>/dev/null
fi

exit 0
