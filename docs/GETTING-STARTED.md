# Getting Started with Claude Logger

Claude Logger automatically captures session data from your Claude Code sessions. This guide walks you through installation, verification, and understanding your session data.

## What Claude Logger Does

Every time you start a Claude Code session, Claude Logger captures:

- **Git state** - commit SHA, branch, dirty files
- **CLAUDE.md content** - your project instructions (full content, not just hash)
- **Skills and commands** - all your custom slash commands
- **MCP servers** - configured Model Context Protocol servers
- **Session metadata** - timestamps, duration, exit reason

This data enables future optimization - comparing session outcomes across different configurations, understanding what works, and improving over time.

## Prerequisites

### Required

- **jq** - JSON processor (the hooks won't work without it)
  ```bash
  # macOS
  brew install jq

  # Ubuntu/Debian
  sudo apt install jq

  # Fedora
  sudo dnf install jq
  ```

- **git** - for capturing repository state

### Required Environment Variable

- **CLAUDE_LOGGER_USER** - Your identifier for session tracking (typically your GitHub username)

  This must be set in your shell profile for sessions to be tracked.

## Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/my-entourage/claude-logger.git
cd claude-logger
```

### Step 2: Choose Installation Mode

Claude Logger supports two installation modes:

| Mode | Command | Best For |
|------|---------|----------|
| **Global** | `./install.sh --global` | Personal use, track all projects in one place |
| **Project** | `./install.sh /path/to/project` | Team projects, sessions stored with project |

#### Option A: Global Installation (Recommended for Personal Use)

```bash
./install.sh --global
```

This installs hooks to `~/.claude/hooks/` and stores all sessions centrally at `~/.claude-logger/sessions/{nickname}/`. Sessions from any project are collected in one location.

#### Option B: Project Installation

```bash
./install.sh /path/to/your-project
```

This installs hooks to the project's `.claude/hooks/` directory. Sessions are stored at `PROJECT/.claude/sessions/{nickname}/`.

Or install to current directory:

```bash
cd /path/to/your-project
/path/to/claude-logger/install.sh
```

The installer will prompt you for your nickname (typically your GitHub username). This is required for session tracking.

### Step 3: Configure Your Environment

Add the `CLAUDE_LOGGER_USER` environment variable to your shell profile (`.bashrc`, `.zshrc`, etc.):

```bash
export CLAUDE_LOGGER_USER="your-nickname"
```

Then reload your shell or run `source ~/.zshrc` (or your profile file).

**Important:** Sessions are only tracked when `CLAUDE_LOGGER_USER` is set. If it's not set, hooks exit silently without tracking.

### Step 4: Verify Installation

Check that files were created:

```bash
ls -la /path/to/your-project/.claude/hooks/
# Should show:
#   session_start.sh
#   session_end.sh
```

Check settings were configured:

```bash
cat /path/to/your-project/.claude/settings.json
# Should show SessionStart and SessionEnd hooks
```

## Using Claude Logger

Once installed, Claude Logger works automatically. There's nothing you need to do.

1. **Start a Claude Code session** in your project
2. **Work normally** - the hooks run invisibly in the background
3. **End your session** - data is captured and saved

### Where Sessions Are Stored

Session storage location depends on your installation mode:

| Mode | Session Path |
|------|--------------|
| Global | `~/.claude-logger/sessions/{nickname}/{session-id}.json` |
| Project | `PROJECT/.claude/sessions/{nickname}/{session-id}.json` |

Each team member's sessions are organized in their own subdirectory based on their `CLAUDE_LOGGER_USER`.

### Viewing Your Sessions

After your first session, explore the data:

```bash
# For global installation:
SESSION_DIR=~/.claude-logger/sessions/$CLAUDE_LOGGER_USER

# For project installation:
SESSION_DIR=.claude/sessions/$CLAUDE_LOGGER_USER

# List your sessions
ls $SESSION_DIR/

# View a session (pretty-printed)
cat $SESSION_DIR/*.json | jq .

# View most recent session
ls -t $SESSION_DIR/*.json | head -1 | xargs cat | jq .
```

## Understanding Session Data

Each session file contains:

```json
{
  "schema_version": 1,
  "session_id": "abc-123-def",
  "transcript_path": "~/.claude/projects/.../abc-123-def.jsonl",
  "status": "complete",

  "start": {
    "timestamp": "2025-12-19T21:00:00Z",
    "cwd": "/Users/you/project",
    "source": "startup",
    "git": {
      "sha": "abc123def456",
      "branch": "main",
      "is_repo": true,
      "dirty": true,
      "dirty_files": ["src/foo.ts"],
      "dirty_count": 1
    },
    "config": {
      "claude_md": "# Your full CLAUDE.md content...",
      "skills": { "commit": "skill content..." },
      "commands": { "test": "command content..." },
      "mcp_servers": ["linear-server"]
    }
  },

  "end": {
    "timestamp": "2025-12-19T21:30:00Z",
    "reason": "logout",
    "duration_seconds": 1800,
    "git": {
      "sha": "def456ghi789",
      "dirty": false,
      "commits_made": ["def456", "ghi789"]
    }
  }
}
```

### Key Fields

| Field | Description |
|-------|-------------|
| `status` | `in_progress`, `complete`, or `incomplete` (crashed) |
| `start.source` | How session started: `startup`, `resume`, `clear`, `compact` |
| `start.git.sha` | Exact commit when session began |
| `end.reason` | How session ended: `logout`, `clear`, `prompt_input_exit`, `other` |
| `end.duration_seconds` | Total session length in seconds |
| `end.git.commits_made` | List of commits created during session |

### Session Statuses

- **in_progress** - Session is currently active
- **complete** - Session ended normally
- **incomplete** - Session crashed or was killed (detected on next session start)

## Installing to Multiple Projects

### Option A: Global Installation (Recommended)

Use `--global` once to track sessions from all projects:

```bash
./install.sh --global
```

All sessions are stored centrally at `~/.claude-logger/sessions/`. Each session records which project (`cwd`) it was run in.

### Option B: Per-Project Installation

Install separately to each project:

```bash
./install.sh ~/project-one
./install.sh ~/project-two
./install.sh ~/project-three
```

Each project maintains its own session history independently in `PROJECT/.claude/sessions/`.

## Querying Session Data

### Find Sessions with Commits

```bash
# Sessions where you made commits
jq 'select(.end.git.commits_made | length > 0)' .claude/sessions/$CLAUDE_LOGGER_USER/*.json
```

### Find Long Sessions

```bash
# Sessions longer than 30 minutes (1800 seconds)
jq 'select(.end.duration_seconds > 1800)' .claude/sessions/$CLAUDE_LOGGER_USER/*.json
```

### Find Crashed Sessions

```bash
# Sessions that didn't end normally
jq 'select(.status == "incomplete")' .claude/sessions/$CLAUDE_LOGGER_USER/*.json
```

### Session Statistics

```bash
# Count your sessions
ls .claude/sessions/$CLAUDE_LOGGER_USER/*.json | wc -l

# Average session duration
jq -s '[.[].end.duration_seconds // 0] | add / length' .claude/sessions/$CLAUDE_LOGGER_USER/*.json

# Total commits across all your sessions
jq -s '[.[].end.git.commits_made // [] | length] | add' .claude/sessions/$CLAUDE_LOGGER_USER/*.json
```

## Troubleshooting

### Sessions Not Being Created

1. **Check CLAUDE_LOGGER_USER is set:**
   ```bash
   echo $CLAUDE_LOGGER_USER
   # Should output your nickname
   ```

   If empty, add to your shell profile:
   ```bash
   export CLAUDE_LOGGER_USER="your-nickname"
   ```

2. **Check jq is installed:**
   ```bash
   jq --version
   # Should output version like "jq-1.7"
   ```

3. **Check hooks are executable:**
   ```bash
   ls -la .claude/hooks/
   # Should show -rwx (executable) permissions
   ```

   Fix with:
   ```bash
   chmod +x .claude/hooks/*.sh
   ```

4. **Check settings.json exists:**
   ```bash
   cat .claude/settings.json
   ```

5. **Test hooks manually:**
   ```bash
   echo '{"session_id":"test-123","cwd":"'$(pwd)'"}' | .claude/hooks/session_start.sh
   ls .claude/sessions/$CLAUDE_LOGGER_USER/
   # Should show test-123.json
   ```

### Permission Denied Errors

The hooks fail gracefully on permission errors. Check directory permissions:

```bash
ls -la .claude/
# .claude/sessions/ needs write permission
```

### Hook Timeout

Hooks have a 10-second timeout. If git operations are slow (large repo), the hook may timeout silently. This doesn't break Claude Code - it just skips capture.

### Existing Hooks Not Working

If you had existing `.claude/settings.json` with other hooks, the installer appends Claude Logger hooks. Verify both exist:

```bash
jq '.hooks' .claude/settings.json
```

## Uninstalling

To remove Claude Logger from a project:

```bash
# Remove hooks
rm -rf .claude/hooks/

# Remove hook configuration from settings.json
# (manual edit - remove SessionStart and SessionEnd entries)

# Optionally remove session data
rm -rf .claude/sessions/
```

## Running Tests

Claude Logger includes a comprehensive test suite:

```bash
cd /path/to/claude-logger

# Run hook tests (103 tests)
bash hooks/tests/test_runner.sh

# Run installer tests (18 tests)
bash tests/test_install.sh
```

This runs 121 tests covering security, edge cases, installation, and stress scenarios.

## What's Next

Session data is currently captured but not analyzed. Future phases will add:

- **Feedback collection** - Rate sessions as good/bad
- **Session analysis** - Identify patterns and pain points
- **Optimization suggestions** - Propose CLAUDE.md improvements

For now, the data accumulates and will be valuable for future optimization work.

## Support

- **Issues:** https://github.com/my-entourage/claude-logger/issues
- **Source:** https://github.com/my-entourage/claude-logger
