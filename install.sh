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

# Add .claude/sessions to .gitignore if not already there
GITIGNORE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -q "^\.claude/sessions" "$GITIGNORE"; then
    echo "" >> "$GITIGNORE"
    echo "# Claude Tracker session data (local only)" >> "$GITIGNORE"
    echo ".claude/sessions/" >> "$GITIGNORE"
  fi
else
  echo "# Claude Tracker session data (local only)" > "$GITIGNORE"
  echo ".claude/sessions/" >> "$GITIGNORE"
fi

echo ""
echo "Claude Tracker installed successfully!"
echo ""
echo "Session data will be saved to: $PROJECT_DIR/.claude/sessions/"
echo "Sessions are automatically captured - no action needed."
echo ""
