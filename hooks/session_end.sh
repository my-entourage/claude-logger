#!/usr/bin/env bash
#
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  DO NOT MODIFY - This file is managed by claude-logger                     ║
# ║  Source: https://github.com/my-entourage/claude-logger                     ║
# ║  To update, re-run the installer from the claude-logger repository.        ║
# ╚════════════════════════════════════════════════════════════════════════════╝
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
# Nickname validation
# Returns 0 if valid, 1 if invalid
# Valid: 1-39 chars, lowercase alphanumeric with dashes/underscores
#######################################
validate_nickname() {
  local nick="$1"
  # Check length and characters
  if [ ${#nick} -lt 1 ] || [ ${#nick} -gt 39 ]; then
    return 1
  fi
  # Check for valid characters only (lowercase alphanumeric, dash, underscore)
  case "$nick" in
    *[!a-z0-9_-]*) return 1 ;;
  esac
  return 0
}

#######################################
# Timeout wrapper (portable: works on macOS and Linux)
# Uses GNU timeout when available, otherwise falls back to direct execution.
# Claude Code has its own 10s hook timeout which provides protection.
#######################################
run_with_timeout() {
  local timeout_seconds="$1"
  shift

  # Use GNU timeout if available (Linux, Homebrew on macOS)
  if command -v timeout &>/dev/null; then
    timeout "$timeout_seconds" "$@"
    return $?
  fi

  # macOS fallback: run directly without timeout wrapper
  # This is acceptable because:
  # 1. Git operations rarely hang in normal conditions
  # 2. Claude Code enforces a 10s hook timeout externally
  # 3. Background process management adds overhead and complexity
  "$@"
}

#######################################
# Resolve project root (git root or fallback to cwd)
# Attempts to find the git repository root directory.
# Falls back to provided cwd if not in a git repo or on timeout.
#######################################
resolve_project_root() {
  local dir="$1"
  local git_timeout=3

  # Try to get git root
  local git_root
  git_root=$(run_with_timeout "$git_timeout" git -C "$dir" rev-parse --show-toplevel 2>/dev/null)

  if [ -n "$git_root" ] && [ -d "$git_root" ]; then
    echo "$git_root"
  else
    echo "$dir"
  fi
}

#######################################
# Read and validate input (single jq call)
#######################################
HOOK_INPUT=$(cat)
[ -z "$HOOK_INPUT" ] && exit 0

# Parse all input fields in single jq call
eval "set -- $(echo "$HOOK_INPUT" | jq -r '[
  .session_id // "",
  .cwd // "",
  .reason // "other"
] | @sh')"
SESSION_ID="$1"
CWD="$2"
EXIT_REASON="$3"

[ -z "$SESSION_ID" ] && exit 0

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Fallback for CWD
if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
  CWD=$(pwd)
fi

# Resolve project root for session storage
PROJECT_ROOT=$(resolve_project_root "$CWD")

#######################################
# Get user nickname (required for tracking)
#######################################
CLAUDE_LOGGER_USER="${CLAUDE_LOGGER_USER:-}"
if [ -z "$CLAUDE_LOGGER_USER" ]; then
  echo "⚠️  CLAUDE_LOGGER_USER not set - session not saved!" >&2
  echo "   Add to your shell profile: export CLAUDE_LOGGER_USER=\"your-username\"" >&2
  exit 0
fi

# Normalize to lowercase
CLAUDE_LOGGER_USER=$(echo "$CLAUDE_LOGGER_USER" | tr '[:upper:]' '[:lower:]')

# Validate nickname
if ! validate_nickname "$CLAUDE_LOGGER_USER"; then
  echo "Warning: CLAUDE_LOGGER_USER '$CLAUDE_LOGGER_USER' is invalid." >&2
  echo "Session tracking skipped." >&2
  exit 0
fi

#######################################
# Determine storage location (global vs project)
#######################################
if [ -f "$HOME/.claude-logger/global-mode" ]; then
  SESSIONS_BASE="$HOME/.claude-logger/sessions/$CLAUDE_LOGGER_USER"
else
  SESSIONS_BASE="$PROJECT_ROOT/.claude/sessions/$CLAUDE_LOGGER_USER"
fi

#######################################
# Locate session file
#######################################
SESSION_FILE="$SESSIONS_BASE/$SESSION_ID.json"

# Only update if session file exists and is readable
if [ ! -f "$SESSION_FILE" ] || [ ! -r "$SESSION_FILE" ]; then
  exit 0
fi

#######################################
# Read all needed values from session file (single jq call)
# This replaces 4+ separate jq calls with one
#######################################
eval "set -- $(jq -r '[
  (if . then "valid" else "invalid" end),
  .status // "",
  .start.git.sha // "",
  .start.timestamp // "",
  .transcript_path // ""
] | @sh' "$SESSION_FILE" 2>/dev/null)"

SESSION_VALID="$1"
SESSION_STATUS="$2"
START_SHA="$3"
START_TS="$4"
TRANSCRIPT_PATH="$5"

# Exit if invalid JSON
[ "$SESSION_VALID" != "valid" ] && exit 0

# Don't update if already complete (idempotent)
[ "$SESSION_STATUS" = "complete" ] && exit 0

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

    # Find commits made during session (uses pre-read START_SHA)
    if [ -n "$START_SHA" ] && [ -n "$sha" ] && [ "$START_SHA" != "$sha" ]; then
      # Verify START_SHA is an ancestor (handles branch switches)
      if run_with_timeout "$git_timeout" git -C "$CWD" merge-base --is-ancestor "$START_SHA" "$sha" 2>/dev/null; then
        commits_made=$(run_with_timeout "$git_timeout" git -C "$CWD" log --format='%H' "$START_SHA..$sha" 2>/dev/null | head -100 | jq -R -s 'split("\n") | map(select(length > 0))') || commits_made="[]"
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
  local duration=0

  # Uses pre-read START_TS from session file
  [ -z "$START_TS" ] && echo "0" && return

  local start_epoch end_epoch

  # Try GNU date first (Linux), then BSD date (macOS)
  if date --version &>/dev/null 2>&1; then
    # GNU date
    start_epoch=$(date -d "$START_TS" "+%s" 2>/dev/null) || start_epoch=0
    end_epoch=$(date -d "$TIMESTAMP" "+%s" 2>/dev/null) || end_epoch=0
  else
    # BSD date (macOS)
    start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$START_TS" "+%s" 2>/dev/null) || start_epoch=0
    end_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$TIMESTAMP" "+%s" 2>/dev/null) || end_epoch=0
  fi

  if [ "$start_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ] && [ "$end_epoch" -ge "$start_epoch" ]; then
    duration=$((end_epoch - start_epoch))
  fi

  echo "$duration"
}

DURATION=$(calculate_duration)

#######################################
# Capture pre-clear transcript snapshot
# When reason is "clear", save transcript before it gets cleared
#######################################
capture_preclear_transcript() {
  local transcript_path="$1"
  local dest_dir="$2"
  local session_id="$3"

  # Only capture if transcript exists and has content
  [ -z "$transcript_path" ] && return 1
  [ ! -f "$transcript_path" ] && return 1
  [ ! -s "$transcript_path" ] && return 1

  local snapshot_file="$dest_dir/${session_id}_preclear.jsonl"
  cp "$transcript_path" "$snapshot_file" 2>/dev/null || return 1

  # Return the snapshot filename for JSON update
  echo "${session_id}_preclear.jsonl"
}

PRECLEAR_SNAPSHOT=""
if [ "$EXIT_REASON" = "clear" ]; then
  PRECLEAR_SNAPSHOT=$(capture_preclear_transcript "$TRANSCRIPT_PATH" "$SESSIONS_BASE" "$SESSION_ID")
fi

#######################################
# Update session file (atomic)
#######################################
TMP_FILE="$SESSION_FILE.tmp.$$"

# Build the jq update command based on whether we have a pre-clear snapshot
if [ -n "$PRECLEAR_SNAPSHOT" ]; then
  jq \
    --arg timestamp "$TIMESTAMP" \
    --arg reason "$EXIT_REASON" \
    --argjson duration "$DURATION" \
    --argjson git "$GIT_END_DATA" \
    --arg clear_ts "$TIMESTAMP" \
    --arg clear_snapshot "$PRECLEAR_SNAPSHOT" \
    '.status = "complete" | .end = {
      timestamp: $timestamp,
      reason: $reason,
      duration_seconds: $duration,
      git: $git
    } | .clear_event = {
      timestamp: $clear_ts,
      transcript_snapshot: $clear_snapshot
    }' "$SESSION_FILE" > "$TMP_FILE" 2>/dev/null
else
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
fi

# Atomic move (only if write succeeded and produced valid JSON)
if [ -s "$TMP_FILE" ] && jq -e '.' "$TMP_FILE" &>/dev/null; then
  mv "$TMP_FILE" "$SESSION_FILE" 2>/dev/null
else
  rm -f "$TMP_FILE" 2>/dev/null
fi

#######################################
# Copy transcript to project-local sessions
# This makes transcripts committable to git
#######################################
copy_transcript() {
  local transcript_path="$1"
  local dest_dir="$2"
  local session_id="$3"

  # Skip if no transcript path
  [ -z "$transcript_path" ] && return 0

  # Skip if transcript doesn't exist or is empty
  [ ! -f "$transcript_path" ] && return 0
  [ ! -s "$transcript_path" ] && return 0

  # Copy transcript to sessions directory
  cp "$transcript_path" "$dest_dir/${session_id}.jsonl" 2>/dev/null || true
}

# TRANSCRIPT_PATH was pre-read from session file earlier
# SESSION_DIR uses SESSIONS_BASE which was set earlier based on global mode
copy_transcript "$TRANSCRIPT_PATH" "$SESSIONS_BASE" "$SESSION_ID"

exit 0
