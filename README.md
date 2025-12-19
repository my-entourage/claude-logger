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

## Install

```bash
git clone https://github.com/ii-vo/claude-tracker.git
cd claude-tracker
./install.sh ~/your-project
```

## How It Works

Uses Claude Code's `SessionStart` and `SessionEnd` hooks to capture enrichment data.

**Claude's data:** `~/.claude/projects/{project}/{session_id}.jsonl`
**Our enrichment:** `.claude/sessions/{session_id}.json` (project-local)

Linked by `session_id`. Query both together for complete picture.

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
      "skills": {
        "commit": "# Full skill content...",
        "debug": "# Full skill content..."
      },
      "mcp_servers": ["linear-server"]
    }
  },
  "end": {
    "timestamp": "2025-12-19T21:30:00Z",
    "reason": "logout",
    "git": {
      "sha": "def456",
      "dirty": false,
      "commits_made": ["def456"]
    }
  }
}
```

## Development

See [docs/PLAN.md](docs/PLAN.md) for implementation details.

## License

MIT
