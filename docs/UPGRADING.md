# Upgrading Claude Logger

This guide covers upgrading from a previous version of Claude Logger.

## What Changed

### Schema Version 2 (Project Organization)

Sessions now include `org` and `repo` fields in the git metadata, extracted from the git remote URL.

### Global Mode: Org/Repo Organization

Global mode now organizes sessions by git org/repo instead of username:

| Version | Global Session Path |
|---------|---------------------|
| Old | `~/.claude-logger/sessions/{username}/{session_id}.json` |
| New | `~/.claude-logger/sessions/{org}/{repo}/{session_id}.json` |

This provides better organization when working across multiple repositories.

### Username No Longer Required for Global Mode

The `CLAUDE_LOGGER_USER` environment variable is now optional for global installs. Sessions are automatically organized by git org/repo.

| Mode | Command | Sessions Stored At | Username Required |
|------|---------|-------------------|-------------------|
| Project | `./install.sh /path/to/project` | `PROJECT/.claude/sessions/{username}/` | Yes |
| Global | `./install.sh --global` | `~/.claude-logger/sessions/{org}/{repo}/` | No |

## Upgrade Steps

### 1. Update Your Shell Profile (Project Mode Only)

For project-level installs, ensure `CLAUDE_LOGGER_USER` is set in your shell profile (`.bashrc`, `.zshrc`, etc.):

```bash
export CLAUDE_LOGGER_USER="your-username"
```

Then reload:

```bash
source ~/.zshrc  # or your profile file
```

For global installs, this step is optional - sessions are organized by git org/repo automatically.

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

This installs hooks once at `~/.claude/hooks/` and stores all sessions at `~/.claude-logger/sessions/{org}/{repo}/`. Sessions are automatically organized by the git remote origin, making it easy to find sessions for any project.

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
