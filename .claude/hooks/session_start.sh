#!/bin/bash
set -euo pipefail

# Read hook input from stdin (JSON)
HOOK_INPUT=$(cat)

# Parse JSON fields using jq
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id')
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty')
SOURCE=$(echo "$HOOK_INPUT" | jq -r '.source // "startup"')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Use CWD from hook input, fallback to current directory
if [ -z "$CWD" ]; then
  CWD=$(pwd)
fi

# Get GitHub username for session directory
GITHUB_USER=$(git config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "unknown")
if [ -z "$GITHUB_USER" ] || [ "$GITHUB_USER" = "unknown" ]; then
  # Try gh CLI as fallback
  GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
fi

# Ensure sessions directory exists (project-local, per-user)
SESSIONS_DIR="$CWD/.claude/sessions/$GITHUB_USER"
mkdir -p "$SESSIONS_DIR"

# Check for orphaned sessions (previous crash) - mark as incomplete
for f in "$SESSIONS_DIR"/*.json; do
  [ -e "$f" ] || continue
  if jq -e '.status == "in_progress"' "$f" > /dev/null 2>&1; then
    jq '.status = "incomplete"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
done

# Capture git state (gracefully handle non-git directories)
GIT_DATA=$(cat <<GITEOF
{
  "sha": "",
  "branch": "",
  "is_repo": false,
  "dirty": false,
  "dirty_files": [],
  "dirty_count": 0
}
GITEOF
)

if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
  GIT_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")
  GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  DIRTY_FILES=$(git -C "$CWD" status --porcelain 2>/dev/null | head -50 | cut -c4- | jq -R -s 'split("\n") | map(select(length > 0))')
  DIRTY_COUNT=$(git -C "$CWD" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  GIT_IS_DIRTY=$([ "$DIRTY_COUNT" -gt 0 ] && echo "true" || echo "false")

  GIT_DATA=$(jq -n \
    --arg sha "$GIT_SHA" \
    --arg branch "$GIT_BRANCH" \
    --argjson dirty "$GIT_IS_DIRTY" \
    --argjson dirty_files "$DIRTY_FILES" \
    --argjson dirty_count "$DIRTY_COUNT" \
    '{
      sha: $sha,
      branch: $branch,
      is_repo: true,
      dirty: $dirty,
      dirty_files: $dirty_files,
      dirty_count: $dirty_count
    }')
fi

# Capture CLAUDE.md content (full content, not hash)
CLAUDE_MD_CONTENT="null"
CLAUDE_MD_PATH=""
if [ -f "$CWD/CLAUDE.md" ]; then
  CLAUDE_MD_CONTENT=$(jq -Rs '.' "$CWD/CLAUDE.md")
  CLAUDE_MD_PATH="$CWD/CLAUDE.md"
fi

# Capture all skills (both global and project-local)
SKILLS_OBJ="{}"

# Global skills
if [ -d "$HOME/.claude/commands" ]; then
  for skill_file in "$HOME/.claude/commands"/*.md; do
    [ -e "$skill_file" ] || continue
    skill_name=$(basename "$skill_file" .md)
    skill_content=$(jq -Rs '.' "$skill_file")
    SKILLS_OBJ=$(echo "$SKILLS_OBJ" | jq --arg name "$skill_name" --argjson content "$skill_content" '. + {($name): $content}')
  done
fi

# Project-local skills (override global)
if [ -d "$CWD/.claude/commands" ]; then
  for skill_file in "$CWD/.claude/commands"/*.md; do
    [ -e "$skill_file" ] || continue
    skill_name=$(basename "$skill_file" .md)
    skill_content=$(jq -Rs '.' "$skill_file")
    SKILLS_OBJ=$(echo "$SKILLS_OBJ" | jq --arg name "$skill_name" --argjson content "$skill_content" '. + {($name): $content}')
  done
fi

# Capture MCP servers
MCP_SERVERS="[]"
if [ -f "$CWD/.mcp.json" ]; then
  MCP_SERVERS=$(jq -r '.mcpServers | keys' "$CWD/.mcp.json" 2>/dev/null || echo "[]")
fi

# Build complete session file using jq (safe JSON construction)
jq -n \
  --argjson schema_version 1 \
  --arg session_id "$SESSION_ID" \
  --arg transcript_path "$TRANSCRIPT_PATH" \
  --arg status "in_progress" \
  --arg timestamp "$TIMESTAMP" \
  --arg cwd "$CWD" \
  --arg source "$SOURCE" \
  --argjson git "$GIT_DATA" \
  --argjson claude_md "$CLAUDE_MD_CONTENT" \
  --arg claude_md_path "$CLAUDE_MD_PATH" \
  --argjson skills "$SKILLS_OBJ" \
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
      git: $git,
      config: {
        claude_md: $claude_md,
        claude_md_path: $claude_md_path,
        skills: $skills,
        mcp_servers: $mcp_servers
      }
    }
  }' > "$SESSIONS_DIR/$SESSION_ID.json"

exit 0
