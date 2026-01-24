#!/usr/bin/env bash
#
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  DO NOT MODIFY - This file is managed by claude-logger                     ║
# ║  Source: https://github.com/my-entourage/claude-logger                     ║
# ║  To update, re-run the installer from the claude-logger repository.        ║
# ╚════════════════════════════════════════════════════════════════════════════╝
#
# Claude Tracker - Pre-Compact Hook
# Captures full transcript before compaction to preserve conversation history.
#
# Design decisions:
# - Same robustness principles as other hooks
# - Captures transcript before Claude Code compacts it
# - Supports multiple compactions per session (incremental counter)
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
# Resolve project root (git root or fallback to cwd)
# Attempts to find the git repository root directory.
# Falls back to provided cwd if not in a git repo or on timeout.
#######################################
resolve_project_root() {
  local dir="$1"
  local git_timeout=3

  # Use GNU timeout if available
  local timeout_cmd=""
  if command -v timeout &>/dev/null; then
    timeout_cmd="timeout $git_timeout"
  fi

  # Try to get git root
  local git_root
  git_root=$($timeout_cmd git -C "$dir" rev-parse --show-toplevel 2>/dev/null)

  if [ -n "$git_root" ] && [ -d "$git_root" ]; then
    echo "$git_root"
  else
    echo "$dir"
  fi
}

#######################################
# Read hook input
#######################################
HOOK_INPUT=$(cat)
[ -z "$HOOK_INPUT" ] && exit 0

#######################################
# Parse input with validation (single jq call)
# PreCompact hook receives: session_id, transcript_path, trigger, cwd
#######################################
eval "set -- $(echo "$HOOK_INPUT" | jq -r '[
  .session_id // "",
  .transcript_path // "",
  .trigger // "auto",
  .cwd // ""
] | @sh')"
SESSION_ID="$1"
TRANSCRIPT_PATH="$2"
TRIGGER="$3"
CWD="$4"

[ -z "$SESSION_ID" ] && exit 0
[ -z "$TRANSCRIPT_PATH" ] && exit 0

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
  exit 0
fi

# Normalize to lowercase
CLAUDE_LOGGER_USER=$(echo "$CLAUDE_LOGGER_USER" | tr '[:upper:]' '[:lower:]')

# Validate nickname
if ! validate_nickname "$CLAUDE_LOGGER_USER"; then
  exit 0
fi

#######################################
# Determine storage location (global vs project)
#######################################
if [ -f "$HOME/.claude-logger/global-mode" ]; then
  SESSIONS_DIR="$HOME/.claude-logger/sessions/$CLAUDE_LOGGER_USER"
else
  SESSIONS_DIR="$PROJECT_ROOT/.claude/sessions/$CLAUDE_LOGGER_USER"
fi

#######################################
# Verify session file exists
#######################################
SESSION_FILE="$SESSIONS_DIR/$SESSION_ID.json"
if [ ! -f "$SESSION_FILE" ] || [ ! -r "$SESSION_FILE" ]; then
  exit 0
fi

#######################################
# Check transcript exists and has content
#######################################
if [ ! -f "$TRANSCRIPT_PATH" ] || [ ! -s "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

#######################################
# Determine next compaction counter
# Count existing precompact files for this session
#######################################
get_next_counter() {
  local count=0
  for f in "$SESSIONS_DIR/${SESSION_ID}_precompact_"*.jsonl; do
    [ -f "$f" ] && ((count++))
  done
  printf "%03d" $((count + 1))
}

COUNTER=$(get_next_counter)
SNAPSHOT_FILE="$SESSIONS_DIR/${SESSION_ID}_precompact_${COUNTER}.jsonl"

#######################################
# Copy transcript to snapshot file
#######################################
cp "$TRANSCRIPT_PATH" "$SNAPSHOT_FILE" 2>/dev/null || exit 0

#######################################
# Update session file with compaction event
#######################################
TMP_FILE="$SESSION_FILE.tmp.$$"

# Add compaction event to session JSON
jq \
  --arg timestamp "$TIMESTAMP" \
  --arg trigger "$TRIGGER" \
  --arg snapshot "${SESSION_ID}_precompact_${COUNTER}.jsonl" \
  '.compaction_events = (.compaction_events // []) + [{
    timestamp: $timestamp,
    trigger: $trigger,
    transcript_snapshot: $snapshot
  }]' "$SESSION_FILE" > "$TMP_FILE" 2>/dev/null

# Atomic move (only if write succeeded and produced valid JSON)
if [ -s "$TMP_FILE" ] && jq -e '.' "$TMP_FILE" &>/dev/null; then
  mv "$TMP_FILE" "$SESSION_FILE" 2>/dev/null
else
  rm -f "$TMP_FILE" 2>/dev/null
fi

exit 0
