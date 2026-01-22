# Upgrading Claude Logger

This guide covers upgrading from a previous version of Claude Logger to the current version with user-based session organization and optional global installation.

## What Changed

### Session Organization (Per-User)

Sessions are now organized by user:

| Version | Session Path |
|---------|--------------|
| Old | `.claude/sessions/{session_id}.json` |
| New | `.claude/sessions/{nickname}/{session_id}.json` |

This allows teams to track sessions per-user and requires the `CLAUDE_LOGGER_USER` environment variable.

### Global Installation Mode (New)

You can now install claude-logger once for all projects using `--global`:

| Mode | Command | Sessions Stored At |
|------|---------|-------------------|
| Project (existing) | `./install.sh /path/to/project` | `PROJECT/.claude/sessions/{nickname}/` |
| Global (new) | `./install.sh --global` | `~/.claude-logger/sessions/{nickname}/` |

## Upgrade Steps

### 1. Update Your Shell Profile

Add `CLAUDE_LOGGER_USER` to your shell profile (`.bashrc`, `.zshrc`, etc.):

```bash
export CLAUDE_LOGGER_USER="your-nickname"
```

Then reload:

```bash
source ~/.zshrc  # or your profile file
```

### 2. Re-run the Installer

From the claude-logger directory:

```bash
./install.sh /path/to/your-project
```

The installer will:
- Prompt for your nickname (validates format)
- Overwrite hooks with the new versions
- Skip adding duplicate hook entries to settings.json
- Create a backup of your existing settings.json

### 3. Verify the Upgrade

```bash
# Check hooks were updated
ls -la /path/to/your-project/.claude/hooks/

# Verify settings.json has hooks configured
jq '.hooks' /path/to/your-project/.claude/settings.json

# Check CLAUDE_LOGGER_USER is set
echo $CLAUDE_LOGGER_USER
```

## Migrating Old Sessions

Old sessions in the flat structure are not automatically migrated. They remain functional and readable, just not organized by user.

### Option A: Leave As-Is

Old sessions stay at `.claude/sessions/{id}.json`. New sessions go to `.claude/sessions/{nickname}/{id}.json`. Both are valid and can be queried.

### Option B: Manual Migration

Move old sessions to your nickname directory:

```bash
cd /path/to/your-project
NICKNAME="your-nickname"

# Create your directory
mkdir -p .claude/sessions/$NICKNAME

# Move old session files (flat structure only)
for f in .claude/sessions/*.json; do
  [ -f "$f" ] && mv "$f" .claude/sessions/$NICKNAME/
done
```

## Upgrading Multiple Projects

### Option A: Switch to Global Mode (Recommended)

Instead of maintaining hooks in each project, use global mode:

```bash
./install.sh --global
```

This installs hooks once at `~/.claude/hooks/` and stores all sessions at `~/.claude-logger/sessions/`. Each session records which project it was run in via the `cwd` field.

**Note:** Global mode takes precedence. Once installed globally, even project-installed hooks will route sessions to the global location.

### Option B: Update Each Project

Run the installer for each project:

```bash
./install.sh ~/project-one
./install.sh ~/project-two
./install.sh ~/project-three
```

Each prompts for nickname and updates independently.

## Troubleshooting

### "Hooks already installed, skipping hook configuration"

This is expected. The installer detected your existing hooks and avoided creating duplicates. Your hook scripts were still updated.

### Sessions Not Being Created After Upgrade

1. Verify `CLAUDE_LOGGER_USER` is set:
   ```bash
   echo $CLAUDE_LOGGER_USER
   ```

2. Restart your shell or run:
   ```bash
   source ~/.zshrc
   ```

3. Start a new Claude Code session (existing sessions won't retroactively track)

### Old Sessions Missing

Old sessions are not deleted or moved. Check:
```bash
# Old location (flat)
ls .claude/sessions/*.json

# New location (per-user)
ls .claude/sessions/$CLAUDE_LOGGER_USER/
```

## Rollback

To revert to the old behavior (not recommended):

1. Remove the `CLAUDE_LOGGER_USER` check from hooks:
   ```bash
   # Edit hooks to remove nickname validation
   vim .claude/hooks/session_start.sh
   vim .claude/hooks/session_end.sh
   ```

2. Change session paths back to flat structure

Or simply unset `CLAUDE_LOGGER_USER` - hooks will exit silently without tracking.
