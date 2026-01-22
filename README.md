# Claude Tracker

Meta-optimization system for Claude Code. Captures session data to enable a feedback loop where Claude Code learns from each session to improve future sessions.

## Overview

Built in two phases:

1. **MVP (Current)**: Capture session data - git state, full config content, session lifecycle
2. **Phase 2 (Future)**: Optimization layer - feedback collection, session analysis, config suggestions

## Why

Claude Code saves full conversation transcripts, but misses:
- Git SHA at session start/end (for A/B testing different configs)
- Full CLAUDE.md and skill contents (not just hashes - needed for optimization)
- Session exit reason and crash detection

This data enables:
- Teaching Claude Code to do tasks faster/better over time
- Comparing session outcomes across different configurations
- Future A/B testing of config changes

## Quick Start

```bash
# 1. Install jq (required)
brew install jq        # macOS
# apt install jq       # Linux

# 2. Clone this repo
git clone https://github.com/my-entourage/claude-logger.git
cd claude-logger

# 3. Install (choose one)
./install.sh --global              # User-level: all projects, sessions in ~/.claude-logger/
./install.sh ~/path/to/project     # Project-level: single project, sessions in project/.claude/

# 4. Add to your shell profile (.bashrc, .zshrc, etc.)
export CLAUDE_LOGGER_USER="your-nickname"
```

Session data is captured automatically on every Claude Code session when `CLAUDE_LOGGER_USER` is set.

**[Full Getting Started Guide](docs/GETTING-STARTED.md)** - detailed installation, verification, and usage instructions.

## How It Works

Uses Claude Code's `SessionStart` and `SessionEnd` hooks to capture enrichment data.

**Claude's data:** `~/.claude/projects/{project}/{session_id}.jsonl`

**Our enrichment (depends on install mode):**

| Mode | Sessions Stored At |
|------|-------------------|
| Global (`--global`) | `~/.claude-logger/sessions/{nickname}/{session_id}.json` |
| Project (default) | `PROJECT/.claude/sessions/{nickname}/{session_id}.json` |

Linked by `session_id`. Query both together for complete picture.

The installer also adds `permissions.deny` rules to prevent Claude from accidentally modifying the hook files.

## Data Captured (MVP)

```json
{
  "schema_version": 1,
  "session_id": "abc-123",
  "transcript_path": "~/.claude/projects/.../abc-123.jsonl",
  "status": "complete",
  "start": {
    "timestamp": "2025-12-19T21:00:00Z",
    "cwd": "/path/to/project",
    "source": "startup",
    "git": {
      "sha": "abc123",
      "branch": "main",
      "dirty": true,
      "dirty_files": ["src/foo.ts"],
      "dirty_count": 1
    },
    "config": {
      "claude_md": "# Full CLAUDE.md content...",
      "skills": { "commit": "..." },
      "commands": { "test": "..." },
      "mcp_servers": ["linear-server"]
    }
  },
  "end": {
    "timestamp": "2025-12-19T21:30:00Z",
    "reason": "logout",
    "duration_seconds": 1800,
    "git": {
      "sha": "def456",
      "dirty": false,
      "commits_made": ["def456"]
    }
  }
}
```

## Documentation

- **[Getting Started](docs/GETTING-STARTED.md)** - Installation, usage, and troubleshooting
- **[Upgrading](docs/UPGRADING.md)** - Migration guide for existing users

## Contributing

Development happens on the `development` branch. PRs go to `development` first, then merge to `main` when tested.

## License

MIT
