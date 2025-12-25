# Upgrading Claude Logger

This guide covers upgrading from a previous version of Claude Logger to the current version with user-based session organization.

## What Changed

The main change is how sessions are organized:

| Version | Session Path |
|---------|--------------|
| Old | `.claude/sessions/{session_id}.json` |
| New | `.claude/sessions/{nickname}/{session_id}.json` |

This allows teams to track sessions per-user and requires the `GITHUB_NICKNAME` environment variable.

## Upgrade Steps

### 1. Update Your Shell Profile

Add `GITHUB_NICKNAME` to your shell profile (`.bashrc`, `.zshrc`, etc.):

```bash
export GITHUB_NICKNAME="your-nickname"
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

# Check GITHUB_NICKNAME is set
echo $GITHUB_NICKNAME
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

1. Verify `GITHUB_NICKNAME` is set:
   ```bash
   echo $GITHUB_NICKNAME
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
ls .claude/sessions/$GITHUB_NICKNAME/
```

## Rollback

To revert to the old behavior (not recommended):

1. Remove the `GITHUB_NICKNAME` check from hooks:
   ```bash
   # Edit hooks to remove nickname validation
   vim .claude/hooks/session_start.sh
   vim .claude/hooks/session_end.sh
   ```

2. Change session paths back to flat structure

Or simply unset `GITHUB_NICKNAME` - hooks will exit silently without tracking.
