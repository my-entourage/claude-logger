# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Logger is a meta-optimization system that captures Claude Code session data to enable analysis and future optimization. It uses Claude Code's SessionStart and SessionEnd hooks to track git state, config snapshots, and session lifecycle.

## Architecture

**Core Components:**
- `hooks/session_start.sh` - Captures initial state (git, CLAUDE.md, skills, commands, MCP servers) at session start
- `hooks/session_end.sh` - Records final git state, commits made, duration, and copies transcript at session end
- `install.sh` - Installs hooks and settings.json to target project directories
- `hooks-config.json` - Template for Claude Code hooks configuration with permissions.deny rules

**Data Flow:**
1. SessionStart hook reads Claude Code input, captures git/config state, writes JSON to `.claude/sessions/{nickname}/{session_id}.json`
2. SessionEnd hook updates session JSON with final state, copies Claude transcript to project
3. Session files are per-user (organized by GITHUB_NICKNAME env var)

**Design Principles:**
- Fail gracefully: hooks never break Claude Code, they silently exit on errors
- Atomic writes: use `.tmp` files then `mv` to prevent corruption
- Bounded operations: timeouts and size limits on all external commands
- Idempotent: safe to run multiple times

## Development Commands

```bash
# Run all hook tests
bash hooks/tests/test_runner.sh

# Run specific test file
bash hooks/tests/test_session_start.sh
bash hooks/tests/test_session_end.sh

# Run installer tests
bash tests/test_install.sh
```

## Testing Notes

- Tests use temporary directories and clean up after themselves
- Hook tests simulate Claude Code input by piping JSON to stdin
- Tests verify atomic writes, lock file handling, orphan detection, edge cases
- `GITHUB_NICKNAME` environment variable must be set (or test mocks it)

## Branch Strategy

Development happens on `development` branch. PRs go to `development` first, then merge to `main` when tested.

## Important Constraints

- `jq` is a required dependency for all hooks
- Hooks have a 10-second timeout in Claude Code
- Session files are capped at 100KB for CLAUDE.md, 50KB per skill/command
- `.claude/hooks/` files are protected by `permissions.deny` rules - do not edit directly; re-run installer to update
