#!/usr/bin/env bash
#
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  DO NOT MODIFY - This file is managed by claude-logger                     ║
# ║  Source: https://github.com/my-entourage/claude-logger                     ║
# ║  To update, re-run the installer from the claude-logger repository.        ║
# ╚════════════════════════════════════════════════════════════════════════════╝
#
# Claude Tracker - Session Start Hook
# Captures git state and config snapshot at session start.
#
# Design decisions:
# - Fail gracefully: never break Claude Code, just skip capture
# - No set -e: individual failures shouldn't abort the hook
# - Atomic writes: write to .tmp then mv to prevent corruption
# - Lock file: prevent concurrent session race conditions
# - Bounded operations: timeouts and limits on all external commands
#

# Fail gracefully - don't use set -e, handle errors explicitly
set -o pipefail

#######################################
# Dependencies check
#######################################
if ! command -v jq &>/dev/null; then
  # jq not installed - silently exit, don't break Claude Code
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
# Extract org and repo from git remote
# Parses SSH or HTTPS remote URLs, falls back to _local/{dirname}
#######################################
extract_org_repo() {
  local dir="$1"
  local git_timeout=3
  local remote_url org repo

  remote_url=$(run_with_timeout "$git_timeout" git -C "$dir" remote get-url origin 2>/dev/null)

  if [ -n "$remote_url" ]; then
    # Parse SSH: git@github.com:org/repo.git
    if [[ "$remote_url" =~ git@[^:]+:([^/]+)/([^/]+)(\.git)?$ ]]; then
      org="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]%.git}"
    # Parse HTTPS: https://github.com/org/repo.git
    elif [[ "$remote_url" =~ https?://[^/]+/([^/]+)/([^/]+)(\.git)?$ ]]; then
      org="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]%.git}"
    fi

    if [ -n "$org" ] && [ -n "$repo" ]; then
      echo "$org" "$repo"
      return 0
    fi
  fi

  # Fallback: _local and directory name
  local dirname
  dirname=$(basename "$dir")
  echo "_local" "$dirname"
}

#######################################
# Read hook input
#######################################
HOOK_INPUT=$(cat)
if [ -z "$HOOK_INPUT" ]; then
  exit 0
fi

#######################################
# Parse input with validation (single jq call)
#######################################
eval "set -- $(echo "$HOOK_INPUT" | jq -r '[
  .session_id // "",
  .transcript_path // "",
  .cwd // "",
  .source // "startup"
] | @sh')"
SESSION_ID="$1"
TRANSCRIPT_PATH="$2"
CWD="$3"
SOURCE="$4"

if [ -z "$SESSION_ID" ]; then
  exit 0  # No session ID = nothing to track
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Fallback for CWD
if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
  CWD=$(pwd)
fi

# Resolve project root for session storage
# Sessions should always be stored at the git root, not in subdirectories
PROJECT_ROOT=$(resolve_project_root "$CWD")

#######################################
# Determine storage location (global vs project)
# Global mode: organize by git org/repo
# Project mode: organize by username (requires CLAUDE_LOGGER_USER)
#######################################
CLAUDE_LOGGER_USER="${CLAUDE_LOGGER_USER:-}"
GIT_ORG=""
GIT_REPO=""

if [ -f "$HOME/.claude-logger/global-mode" ]; then
  # Global mode: organize by org/repo, username not required
  read -r GIT_ORG GIT_REPO <<< "$(extract_org_repo "$PROJECT_ROOT")"
  SESSIONS_DIR="$HOME/.claude-logger/sessions/$GIT_ORG/$GIT_REPO"

  # If username is set, validate and normalize (optional for global mode)
  if [ -n "$CLAUDE_LOGGER_USER" ]; then
    CLAUDE_LOGGER_USER=$(echo "$CLAUDE_LOGGER_USER" | tr '[:upper:]' '[:lower:]')
    if ! validate_nickname "$CLAUDE_LOGGER_USER"; then
      # Invalid username, just clear it (non-fatal in global mode)
      CLAUDE_LOGGER_USER=""
    fi
  fi
else
  # Project mode: organize by username (required)
  if [ -z "$CLAUDE_LOGGER_USER" ]; then
    echo "⚠️  CLAUDE_LOGGER_USER not set - session tracking disabled!" >&2
    echo "   Add to your shell profile: export CLAUDE_LOGGER_USER=\"your-username\"" >&2
    echo "   Then restart your terminal or run: source ~/.zshrc" >&2
    exit 0
  fi

  # Normalize to lowercase
  CLAUDE_LOGGER_USER=$(echo "$CLAUDE_LOGGER_USER" | tr '[:upper:]' '[:lower:]')

  # Validate nickname
  if ! validate_nickname "$CLAUDE_LOGGER_USER"; then
    echo "Warning: CLAUDE_LOGGER_USER '$CLAUDE_LOGGER_USER' is invalid." >&2
    echo "Must be 1-39 characters, lowercase alphanumeric with dashes/underscores only." >&2
    echo "Session tracking skipped." >&2
    exit 0
  fi

  SESSIONS_DIR="$PROJECT_ROOT/.claude/sessions/$CLAUDE_LOGGER_USER"

  # Extract org/repo for metadata (even in project mode)
  read -r GIT_ORG GIT_REPO <<< "$(extract_org_repo "$PROJECT_ROOT")"
fi

#######################################
# Setup directories
#######################################
mkdir -p "$SESSIONS_DIR" 2>/dev/null || exit 0  # Can't create dir = can't track

SESSION_FILE="$SESSIONS_DIR/$SESSION_ID.json"
LOCK_FILE="$SESSIONS_DIR/.lock"

#######################################
# Acquire lock (with timeout)
# Prevents race conditions with concurrent sessions
#######################################
acquire_lock() {
  local timeout=5
  local count=0
  while [ -f "$LOCK_FILE" ] && [ $count -lt $timeout ]; do
    sleep 1
    ((count++))
  done
  echo $$ > "$LOCK_FILE" 2>/dev/null
}

release_lock() {
  rm -f "$LOCK_FILE" 2>/dev/null
}

# Ensure lock is released on exit
trap release_lock EXIT
acquire_lock

#######################################
# Mark orphaned sessions (only recent ones)
# Only check files modified in last 24 hours to avoid O(n) on old sessions
# Note: This runs AFTER session creation to avoid blocking
#######################################
mark_orphans() {
  # Use find with -mtime to limit scope
  if command -v find &>/dev/null; then
    find "$SESSIONS_DIR" -maxdepth 1 -name "*.json" -type f -mtime -1 2>/dev/null | while IFS= read -r f; do
      [ -f "$f" ] || continue
      # Skip our own session file
      [ "$f" = "$SESSION_FILE" ] && continue
      # Check if in_progress and mark incomplete
      if jq -e '.status == "in_progress"' "$f" &>/dev/null; then
        jq '.status = "incomplete" | .end.reason = "orphaned"' "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" 2>/dev/null
      fi
    done
  fi
}
# NOTE: mark_orphans is called AFTER session file is written (see end of script)

#######################################
# Capture git state (with timeouts)
#######################################
capture_git() {
  local git_timeout=3  # seconds

  # Check if git repo (fast check)
  if ! run_with_timeout "$git_timeout" git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
    echo '{"sha":"","branch":"","is_repo":false,"dirty":false,"dirty_files":[],"dirty_count":0}'
    return
  fi

  local sha branch dirty_count is_dirty dirty_files

  sha=$(run_with_timeout "$git_timeout" git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")
  branch=$(run_with_timeout "$git_timeout" git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  # Get dirty files with limit (avoid huge output)
  local porcelain
  porcelain=$(run_with_timeout "$git_timeout" git -C "$CWD" status --porcelain 2>/dev/null | head -100) || porcelain=""
  dirty_count=$(echo "$porcelain" | grep -c . 2>/dev/null || echo "0")
  # Ensure dirty_count is a valid integer
  dirty_count=$(echo "$dirty_count" | tr -d '\n' | grep -E '^[0-9]+$' || echo "0")
  [ -z "$dirty_count" ] && dirty_count=0

  if [ "$dirty_count" -gt 0 ]; then
    is_dirty="true"
    # Extract filenames, handle spaces properly
    dirty_files=$(echo "$porcelain" | head -50 | cut -c4- | jq -R -s 'split("\n") | map(select(length > 0))')
  else
    is_dirty="false"
    dirty_files="[]"
  fi

  jq -n \
    --arg sha "$sha" \
    --arg branch "$branch" \
    --argjson dirty "$is_dirty" \
    --argjson dirty_files "$dirty_files" \
    --argjson dirty_count "$dirty_count" \
    '{sha: $sha, branch: $branch, is_repo: true, dirty: $dirty, dirty_files: $dirty_files, dirty_count: $dirty_count}'
}

GIT_DATA=$(capture_git)

#######################################
# Capture CLAUDE.md
#######################################
capture_claude_md() {
  local claude_md_file="$CWD/CLAUDE.md"
  if [ -f "$claude_md_file" ] && [ -r "$claude_md_file" ]; then
    # Limit size to 100KB to prevent memory issues
    local size
    size=$(wc -c < "$claude_md_file" | tr -d ' ')
    if [ "$size" -lt 102400 ]; then
      jq -Rs '.' "$claude_md_file"
    else
      echo '"[CLAUDE.md too large - exceeded 100KB limit]"'
    fi
  else
    echo 'null'
  fi
}

CLAUDE_MD_CONTENT=$(capture_claude_md)
CLAUDE_MD_PATH=""
[ -f "$CWD/CLAUDE.md" ] && CLAUDE_MD_PATH="$CWD/CLAUDE.md"

#######################################
# Capture skills and commands
# Limit total size to prevent memory issues
# Optimized: collects entries then builds JSON object in one jq call
#######################################
capture_config_files() {
  local dir_type="$1"  # "skills" or "commands"
  local total_size=0
  local max_total=524288  # 512KB total limit
  local max_file=51200    # 50KB per file limit
  local entries=""        # Accumulate JSON key-value pairs

  # Helper to add a file to entries (1 jq call per file, no merge call)
  add_entry() {
    local name="$1" file="$2"
    local content
    content=$(jq -Rs '.' "$file" 2>/dev/null) || return
    # Append as JSON fragment: "name": content
    if [ -n "$entries" ]; then
      entries="$entries,"
    fi
    # Use jq to safely escape the name (handles special chars)
    local escaped_name
    escaped_name=$(printf '%s' "$name" | jq -Rs '.')
    entries="$entries$escaped_name:$content"
  }

  # Helper to process a directory
  process_dir() {
    local base_dir="$1"
    [ -d "$base_dir" ] || return

    if [ "$dir_type" = "skills" ]; then
      # Skills: look for SKILL.md in subdirectories
      for skill_dir in "$base_dir"/*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name skill_file file_size
        skill_name=$(basename "$skill_dir")
        skill_file="$skill_dir/SKILL.md"
        [ -f "$skill_file" ] && [ -r "$skill_file" ] || continue

        file_size=$(wc -c < "$skill_file" | tr -d ' ')
        [ "$file_size" -gt "$max_file" ] && continue
        total_size=$((total_size + file_size))
        [ "$total_size" -gt "$max_total" ] && break

        add_entry "$skill_name" "$skill_file"
      done
    else
      # Commands: look for *.md files directly
      for cmd_file in "$base_dir"/*.md; do
        [ -f "$cmd_file" ] && [ -r "$cmd_file" ] || continue
        local cmd_name file_size
        cmd_name=$(basename "$cmd_file" .md)

        file_size=$(wc -c < "$cmd_file" | tr -d ' ')
        [ "$file_size" -gt "$max_file" ] && continue
        total_size=$((total_size + file_size))
        [ "$total_size" -gt "$max_total" ] && break

        add_entry "$cmd_name" "$cmd_file"
      done
    fi
  }

  # Process global first, then project-local (project overrides global)
  process_dir "$HOME/.claude/$dir_type"
  process_dir "$CWD/.claude/$dir_type"

  # Build final JSON object (no additional jq merge calls needed)
  echo "{$entries}"
}

SKILLS_OBJ=$(capture_config_files "skills")
COMMANDS_OBJ=$(capture_config_files "commands")

#######################################
# Capture MCP servers
#######################################
MCP_SERVERS="[]"
if [ -f "$CWD/.mcp.json" ] && [ -r "$CWD/.mcp.json" ]; then
  MCP_SERVERS=$(jq '.mcpServers // {} | keys' "$CWD/.mcp.json" 2>/dev/null || echo "[]")
fi

#######################################
# Build and write session file (atomic)
#######################################
TMP_FILE="$SESSION_FILE.tmp.$$"

jq -n \
  --argjson schema_version 2 \
  --arg session_id "$SESSION_ID" \
  --arg transcript_path "$TRANSCRIPT_PATH" \
  --arg status "in_progress" \
  --arg timestamp "$TIMESTAMP" \
  --arg cwd "$CWD" \
  --arg source "$SOURCE" \
  --argjson git "$GIT_DATA" \
  --arg git_org "$GIT_ORG" \
  --arg git_repo "$GIT_REPO" \
  --argjson claude_md "$CLAUDE_MD_CONTENT" \
  --arg claude_md_path "$CLAUDE_MD_PATH" \
  --argjson skills "$SKILLS_OBJ" \
  --argjson commands "$COMMANDS_OBJ" \
  --argjson mcp_servers "$MCP_SERVERS" \
  '{
    schema_version: $schema_version,
    session_id: $session_id,
    transcript_path: $transcript_path,
    status: $status,
    start: {
      timestamp: $timestamp,
      cwd: $cwd,
      source: $source,
      git: ($git + {org: $git_org, repo: $git_repo}),
      config: {
        claude_md: $claude_md,
        claude_md_path: $claude_md_path,
        skills: $skills,
        commands: $commands,
        mcp_servers: $mcp_servers
      }
    }
  }' > "$TMP_FILE" 2>/dev/null

# Atomic move (only if write succeeded)
if [ -s "$TMP_FILE" ]; then
  mv "$TMP_FILE" "$SESSION_FILE" 2>/dev/null
else
  rm -f "$TMP_FILE" 2>/dev/null
fi

#######################################
# Mark orphaned sessions (non-blocking)
# Run AFTER our session is created so it doesn't block session creation
# Safe to run without lock since we only update OTHER sessions
#######################################
release_lock
trap - EXIT  # Clear trap since we manually released
mark_orphans

exit 0
