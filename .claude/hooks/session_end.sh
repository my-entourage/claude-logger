#!/bin/bash
set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Parse JSON fields
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id')
CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty')
EXIT_REASON=$(echo "$HOOK_INPUT" | jq -r '.reason // "other"')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ -z "$CWD" ]; then
  CWD=$(pwd)
fi

# Get GitHub username for session directory
GITHUB_USER=$(git config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "unknown")
if [ -z "$GITHUB_USER" ] || [ "$GITHUB_USER" = "unknown" ]; then
  # Try gh CLI as fallback
  GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
fi

SESSION_FILE="$CWD/.claude/sessions/$GITHUB_USER/$SESSION_ID.json"

# Only update if session file exists
if [ ! -f "$SESSION_FILE" ]; then
  exit 0
fi

# Capture end git state
GIT_SHA=""
GIT_DIRTY="false"
COMMITS_MADE="[]"

if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
  GIT_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")
  GIT_DIRTY=$([ -n "$(git -C "$CWD" status --porcelain 2>/dev/null)" ] && echo "true" || echo "false")

  # Find commits made during session (compare start SHA to current)
  START_SHA=$(jq -r '.start.git.sha // ""' "$SESSION_FILE")
  if [ -n "$START_SHA" ] && [ -n "$GIT_SHA" ] && [ "$START_SHA" != "$GIT_SHA" ]; then
    COMMITS_MADE=$(git -C "$CWD" log --format='%H' "$START_SHA..$GIT_SHA" 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' || echo "[]")
  fi
fi

# Update session file with end data
jq \
  --arg timestamp "$TIMESTAMP" \
  --arg reason "$EXIT_REASON" \
  --arg sha "$GIT_SHA" \
  --argjson dirty "$GIT_DIRTY" \
  --argjson commits "$COMMITS_MADE" \
  '.status = "complete" | .end = {
    timestamp: $timestamp,
    reason: $reason,
    git: {
      sha: $sha,
      dirty: $dirty,
      commits_made: $commits
    }
  }' "$SESSION_FILE" > "$SESSION_FILE.tmp" && mv "$SESSION_FILE.tmp" "$SESSION_FILE"

exit 0
