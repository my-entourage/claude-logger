# Claude Tracker Implementation Plan

## Overview

Claude Tracker is a meta-optimization system for Claude Code, built in two phases:

1. **MVP (This Document)**: Capture session data - git state, full config content, session lifecycle
2. **Phase 2 (Future)**: Optimization layer - feedback collection, session analysis, config suggestions

**Primary Goal:** Enable a feedback loop where Claude Code learns from each session to improve future sessions - teaching Claude Code to do things faster and better over time.

**MVP Goal:** Reliably capture all data needed for future optimization, with zero user intervention.

## Current State Analysis

### What Claude Code Already Captures

Location: `~/.claude/projects/{project-path-encoded}/{session_id}.jsonl`

| Data | Captured | Format |
|------|----------|--------|
| Full conversation | Yes | JSONL with user/assistant messages |
| Tool calls + results | Yes | Inline in assistant messages |
| Thinking blocks | Yes | `type: "thinking"` |
| Git branch | Yes | `gitBranch` field per message |
| Working directory | Yes | `cwd` field |
| Timestamps | Yes | ISO8601 `timestamp` field |
| Session ID | Yes | `sessionId` field |
| Claude Code version | Yes | `version` field |
| Commits made | Yes | As Bash tool calls with `git commit` |

### What's Missing (What We Capture)

| Data | Why It Matters |
|------|----------------|
| Git SHA at session start | Know exact codebase state for future A/B testing |
| Git SHA at session end | Know what commits were made |
| Actual CLAUDE.md content | Know what instructions were active (for optimization) |
| Actual skill contents | Know what skills were available (for optimization) |
| User feedback (rating + text) | Know if session was good/bad and why |
| Task summary | Know what user was trying to accomplish |
| Optimization history | Track what changes were made and their impact |

## Desired End State (MVP)

After MVP implementation:

1. **SessionStart hook** automatically captures git state + full config content
2. **SessionEnd hook** captures end state and marks session complete
3. Data stored project-locally in `.claude/sessions/{github-username}/` for future optimization
4. Crashed sessions silently marked incomplete (detected on next session start)
5. Zero user intervention required - all capture is automatic

### Verification

```bash
# After any Claude Code session:
cat .claude/sessions/{github-username}/{session_id}.json

# Should contain:
# - start: git state, full CLAUDE.md content, all skill contents
# - end: git state, commits made, exit reason
# - status: "complete" or "incomplete" (if crashed)
```

## What We're NOT Doing (MVP)

- Feedback collection (Phase 2)
- Session analysis (Phase 2)
- Optimization suggestions (Phase 2)
- `/learn` and `/commit-and-learn` skills (Phase 2)
- Team sync / central storage
- Automated A/B testing execution
- Impact tracking / regression detection
- UI / dashboard

## Data Schema (MVP)

### Session File: `.claude/sessions/{github-username}/{session_id}.json`

```json
{
  "schema_version": 1,
  "session_id": "abc-123-def",
  "transcript_path": "~/.claude/projects/-project-path/abc-123-def.jsonl",
  "status": "complete",

  "start": {
    "timestamp": "2025-12-19T21:00:00Z",
    "cwd": "/Users/ia/project",
    "source": "startup",
    "git": {
      "sha": "abc123def456",
      "branch": "main",
      "is_repo": true,
      "dirty": true,
      "dirty_files": ["src/foo.ts", "README.md"],
      "dirty_count": 2
    },
    "config": {
      "claude_md": "# Project Instructions\n\nThis project uses...",
      "claude_md_path": "/Users/ia/project/CLAUDE.md",
      "skills": {
        "commit": "# Commit Changes\n\nYou are tasked with...",
        "debug": "# Debug Issues\n\n..."
      },
      "mcp_servers": ["linear-server"]
    }
  },

  "end": {
    "timestamp": "2025-12-19T21:30:00Z",
    "reason": "logout",
    "git": {
      "sha": "def456ghi789",
      "dirty": false,
      "commits_made": ["def456", "ghi789"]
    }
  }
}
```

**Note:** `feedback` and `optimization` fields will be added in Phase 2.

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Not a git repo | `git.is_repo: false`, other git fields empty |
| No CLAUDE.md | `config.claude_md: null` |
| No skills | `config.skills: {}` |
| Session crash | `status: "incomplete"`, `end` block missing, detected on next start |
| Very large CLAUDE.md | Captured fully (optimize later if needed) |
| Many dirty files (50+) | Capture first 50 + count |
| Concurrent sessions | Separate files by session_id, no conflict |
| Resumed session | `source: "resume"` in start block |

---

## Phase 1: Session Hooks (Data Capture)

### Overview

Create hooks that capture git state and full config content at session boundaries. Use correct Claude Code hooks format based on official documentation.

### Changes Required

#### 1. Session Start Hook

**File**: `hooks/session_start.sh`

```bash
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
```

#### 2. Session End Hook

**File**: `hooks/session_end.sh`

```bash
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
```

#### 3. Hooks Configuration

**File**: `hooks-config.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session_start.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session_end.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Success Criteria

#### Automated Verification:
- [ ] Hook scripts exist and are executable: `ls -la .claude/hooks/`
- [ ] Start hook creates valid JSON: `echo '{"session_id":"test","cwd":"'$(pwd)'"}' | .claude/hooks/session_start.sh && jq . .claude/sessions/$(git config user.name | tr ' ' '-' | tr '[:upper:]' '[:lower:]')/test.json`
- [ ] End hook updates JSON: `echo '{"session_id":"test","cwd":"'$(pwd)'","reason":"logout"}' | .claude/hooks/session_end.sh && jq '.end' .claude/sessions/$(git config user.name | tr ' ' '-' | tr '[:upper:]' '[:lower:]')/test.json`
- [ ] Non-git directory handled: Test in `/tmp`

#### Manual Verification:
- [ ] Start Claude Code session, verify `.claude/sessions/{github-username}/{id}.json` created
- [ ] Verify CLAUDE.md content is captured (not just hash)
- [ ] Verify skills are captured with full content
- [ ] End session, verify `end` block added with correct reason
- [ ] Verify crashed session detection works (kill Claude Code, restart, check status)

---

## Phase 2: Installation Script

### Overview

Create installation script that copies hooks to project and merges config safely.

### Changes Required

#### 1. Install Script

**File**: `install.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "Installing Claude Tracker..."

# Determine project directory (where to install)
if [ -n "${1:-}" ]; then
  PROJECT_DIR="$1"
else
  PROJECT_DIR=$(pwd)
fi

# Validate it's a reasonable project directory
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: $PROJECT_DIR is not a directory"
  exit 1
fi

# Create directories
mkdir -p "$PROJECT_DIR/.claude/hooks"
mkdir -p "$PROJECT_DIR/.claude/sessions"

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Copy hooks
cp "$SCRIPT_DIR/hooks/session_start.sh" "$PROJECT_DIR/.claude/hooks/"
cp "$SCRIPT_DIR/hooks/session_end.sh" "$PROJECT_DIR/.claude/hooks/"
chmod +x "$PROJECT_DIR/.claude/hooks/session_start.sh"
chmod +x "$PROJECT_DIR/.claude/hooks/session_end.sh"

# Handle settings.json - need to APPEND hooks, not replace
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"
HOOKS_CONFIG="$SCRIPT_DIR/hooks-config.json"

if [ -f "$SETTINGS_FILE" ]; then
  # Backup existing
  cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"

  # Check if hooks already exist
  if jq -e '.hooks.SessionStart' "$SETTINGS_FILE" > /dev/null 2>&1; then
    echo "Warning: SessionStart hooks already exist in settings.json"
    echo "Appending Claude Tracker hooks to existing configuration..."

    # Append our hooks to existing arrays
    TRACKER_START_HOOK=$(jq '.hooks.SessionStart[0]' "$HOOKS_CONFIG")
    TRACKER_END_HOOK=$(jq '.hooks.SessionEnd[0]' "$HOOKS_CONFIG")

    jq --argjson start "$TRACKER_START_HOOK" --argjson end "$TRACKER_END_HOOK" \
      '.hooks.SessionStart += [$start] | .hooks.SessionEnd += [$end]' \
      "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  else
    # No existing hooks, merge normally
    jq -s '.[0] * .[1]' "$SETTINGS_FILE" "$HOOKS_CONFIG" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  fi
else
  # No existing settings, copy hooks config
  cp "$HOOKS_CONFIG" "$SETTINGS_FILE"
fi

echo ""
echo "Claude Tracker installed successfully!"
echo ""
echo "Session data will be saved to: $PROJECT_DIR/.claude/sessions/{github-username}/"
echo "Sessions are automatically captured - no action needed."
echo ""
```

### Success Criteria

#### Automated Verification:
- [ ] Install script runs without errors: `./install.sh /tmp/test-project`
- [ ] Hooks are installed: `ls -la /tmp/test-project/.claude/hooks/`
- [ ] Settings created/updated: `jq '.hooks' /tmp/test-project/.claude/settings.json`

#### Manual Verification:
- [ ] Install on project with existing .claude/settings.json preserves other settings
- [ ] Install on project with existing hooks appends, doesn't replace
- [ ] Re-running install is safe (idempotent)

---

## Phase 3: Testing & Verification

### Overview

Comprehensive testing of the data capture flow.

### Test Scenarios

1. **Happy path**: Start session → work → exit → verify complete session file

2. **Git repo**: Verify SHA, branch, dirty files captured correctly

3. **Non-git directory**: Works without git, captures config only

4. **No CLAUDE.md**: `config.claude_md` is null, no error

5. **Large CLAUDE.md**: Handles big files (test with 10KB+ file)

6. **Many skills**: All skills captured correctly

7. **Concurrent sessions**: Two terminals, same project, separate session files

8. **Session crash**: Kill Claude Code mid-session → next session marks previous as incomplete

9. **Resumed session**: Use `--resume` → `source: "resume"` captured

10. **Commits during session**: Make commits → `commits_made` list populated at end

### Manual Testing Steps

1. Install to a test project: `./install.sh ~/test-project`
2. Start Claude Code in test project
3. Verify `.claude/sessions/{github-username}/{id}.json` created with correct start data
4. Verify CLAUDE.md content captured (not hash)
5. Verify skills captured with full content
6. Make a commit during session
7. Exit session normally
8. Verify `end` block with correct reason and `commits_made`
9. Kill Claude Code in another session (Ctrl+C or kill process)
10. Start new session, verify previous marked as "incomplete"
11. Test in non-git directory (e.g., `/tmp/test`)

---

## Performance Considerations

- **Hook timeout**: 10 seconds (should complete in <1 second for most projects)
- **Large CLAUDE.md**: Up to 50KB should be fine, can optimize later if needed
- **Many skills**: Capture all, but pagination possible if >100
- **Git operations**: Fast for typical repos, may be slow for huge monorepos

---

## Future: Phase 2 - Optimization Layer

After MVP is stable, implement the optimization layer:

### Components

1. **`/learn` skill**: Collect feedback, analyze session, suggest improvements
2. **`/commit-and-learn` skill**: Commit + learn in one command
3. **Feedback collection**: Rating (👍/👎) + freeform text + task summary
4. **Session analysis**: Identify pain points from transcript
5. **Suggestion generation**: Propose CLAUDE.md changes or new skills
6. **Change application**: Apply accepted suggestions to config

### Data Schema Additions

```json
{
  "feedback": {
    "rating": "positive|negative",
    "text": "user's feedback text or null",
    "task_summary": "what user was trying to do",
    "collected_at": "ISO timestamp"
  },
  "optimization": {
    "analyzed_at": "ISO timestamp",
    "suggestions": [...],
    "changes_made": [...]
  }
}
```

### Key Design Decisions (Already Made)

- Feedback only collected on commit sessions (via `/commit-and-learn`)
- Suggestions must be generalizable, not specific to exact files
- 1-3 suggestions per session, conservative approach
- User approves each suggestion before applying

---

## Future: Phase 3+ Considerations

1. **Impact tracking**: Compare session ratings before/after optimizations
2. **A/B testing**: Branch from start SHA, apply different configs, compare
3. **Cross-project patterns**: Learn from multiple projects
4. **Team sharing**: Export/import optimizations
5. **Rollback**: Undo optimizations that made things worse
6. **Auto-suggestions**: Proactively suggest based on patterns without waiting for feedback

---

## References

- Claude Code Hooks: https://docs.anthropic.com/en/docs/claude-code/hooks
- Session data location: `~/.claude/projects/`
- This plan: `docs/PLAN.md`
