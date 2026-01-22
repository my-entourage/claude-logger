#!/bin/bash
set -euo pipefail

echo "Installing Claude Tracker..."

#######################################
# Parse --global flag
#######################################
GLOBAL_MODE=false
if [ "${1:-}" = "--global" ]; then
  GLOBAL_MODE=true
  shift
fi

#######################################
# Nickname validation
# Returns 0 if valid, 1 if invalid
# Valid: 1-39 chars, lowercase alphanumeric with dashes/underscores
#######################################
validate_nickname() {
  local nick="$1"
  # Check length and characters
  if [ ${#nick} -lt 1 ] || [ ${#nick} -gt 39 ]; then
    return 1
  fi
  # Check for valid characters only (lowercase alphanumeric, dash, underscore)
  case "$nick" in
    *[!a-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# Determine installation directory
if [ "$GLOBAL_MODE" = true ]; then
  INSTALL_DIR="$HOME/.claude"
  SESSIONS_DIR="$HOME/.claude-logger/sessions"
  PROJECT_DIR=""  # Not applicable for global mode
else
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

  INSTALL_DIR="$PROJECT_DIR/.claude"
  SESSIONS_DIR="$PROJECT_DIR/.claude/sessions"
fi

#######################################
# Get user identifier (from env or prompt)
#######################################
CLAUDE_LOGGER_USER="${CLAUDE_LOGGER_USER:-}"
NICKNAME_FROM_ENV=false

# Check if already set in environment
if [ -n "$CLAUDE_LOGGER_USER" ]; then
  # Normalize to lowercase
  CLAUDE_LOGGER_USER=$(echo "$CLAUDE_LOGGER_USER" | tr '[:upper:]' '[:lower:]')

  if validate_nickname "$CLAUDE_LOGGER_USER"; then
    echo ""
    echo "Using CLAUDE_LOGGER_USER from environment: $CLAUDE_LOGGER_USER"
    NICKNAME_FROM_ENV=true
  else
    echo "Warning: CLAUDE_LOGGER_USER '$CLAUDE_LOGGER_USER' is invalid, prompting for new one."
    CLAUDE_LOGGER_USER=""
  fi
fi

# Prompt if not set or invalid
if [ -z "$CLAUDE_LOGGER_USER" ]; then
  echo ""
  echo "Claude Tracker requires a username to organize your sessions."
  echo "This should be your GitHub username or a consistent identifier."
  echo "(Valid: 1-39 characters, lowercase letters, numbers, dashes, underscores)"
  echo ""

  while true; do
    read -p "Enter your username: " CLAUDE_LOGGER_USER

    # Normalize to lowercase
    CLAUDE_LOGGER_USER=$(echo "$CLAUDE_LOGGER_USER" | tr '[:upper:]' '[:lower:]')

    if [ -z "$CLAUDE_LOGGER_USER" ]; then
      echo "Error: Username cannot be empty. Please try again."
      continue
    fi

    if validate_nickname "$CLAUDE_LOGGER_USER"; then
      break
    else
      echo "Error: Invalid username '$CLAUDE_LOGGER_USER'."
      echo "Must be 1-39 characters, lowercase alphanumeric with dashes/underscores only."
      echo "Please try again."
    fi
  done

  echo ""
  echo "Using username: $CLAUDE_LOGGER_USER"
fi

# Create directories
mkdir -p "$INSTALL_DIR/hooks"

# For global mode, also create the sessions directory and marker
if [ "$GLOBAL_MODE" = true ]; then
  mkdir -p "$HOME/.claude-logger"
  touch "$HOME/.claude-logger/global-mode"
fi

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

#######################################
# Check if a hook command already exists
# Returns 0 if exists, 1 if not
#######################################
hook_exists() {
  local settings_file="$1"
  local hook_type="$2"  # "SessionStart" or "SessionEnd"
  local command_pattern="$3"

  if [ ! -f "$settings_file" ]; then
    return 1
  fi

  # Check if any hook contains the command pattern
  jq -e ".hooks.${hook_type}[]?.hooks[]? | select(.command | contains(\"$command_pattern\"))" "$settings_file" > /dev/null 2>&1
}

# Copy hooks
cp "$SCRIPT_DIR/hooks/session_start.sh" "$INSTALL_DIR/hooks/"
cp "$SCRIPT_DIR/hooks/session_end.sh" "$INSTALL_DIR/hooks/"
cp "$SCRIPT_DIR/hooks/pre_compact.sh" "$INSTALL_DIR/hooks/"
chmod +x "$INSTALL_DIR/hooks/session_start.sh"
chmod +x "$INSTALL_DIR/hooks/session_end.sh"
chmod +x "$INSTALL_DIR/hooks/pre_compact.sh"

# Handle settings.json - need to APPEND hooks, not replace
SETTINGS_FILE="$INSTALL_DIR/settings.json"
HOOKS_CONFIG="$SCRIPT_DIR/hooks-config.json"

# For global mode, we need to generate hook config with absolute paths
# Create a temp file with the processed config
HOOKS_CONFIG_PROCESSED=$(mktemp)
trap "rm -f '$HOOKS_CONFIG_PROCESSED'" EXIT

if [ "$GLOBAL_MODE" = true ]; then
  jq \
    --arg start_cmd "$INSTALL_DIR/hooks/session_start.sh" \
    --arg end_cmd "$INSTALL_DIR/hooks/session_end.sh" \
    --arg precompact_cmd "$INSTALL_DIR/hooks/pre_compact.sh" \
    '.hooks.SessionStart[0].hooks[0].command = $start_cmd | .hooks.SessionEnd[0].hooks[0].command = $end_cmd | .hooks.PreCompact[0].hooks[0].command = $precompact_cmd' \
    "$HOOKS_CONFIG" > "$HOOKS_CONFIG_PROCESSED"
else
  cp "$HOOKS_CONFIG" "$HOOKS_CONFIG_PROCESSED"
fi

if [ -f "$SETTINGS_FILE" ]; then
  # Backup existing
  cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"

  # Check for duplicate hooks before adding
  START_EXISTS=false
  END_EXISTS=false
  PRECOMPACT_EXISTS=false

  if hook_exists "$SETTINGS_FILE" "SessionStart" "session_start.sh"; then
    START_EXISTS=true
    echo "Note: SessionStart hook already configured, skipping..."
  fi

  if hook_exists "$SETTINGS_FILE" "SessionEnd" "session_end.sh"; then
    END_EXISTS=true
    echo "Note: SessionEnd hook already configured, skipping..."
  fi

  if hook_exists "$SETTINGS_FILE" "PreCompact" "pre_compact.sh"; then
    PRECOMPACT_EXISTS=true
    echo "Note: PreCompact hook already configured, skipping..."
  fi

  if [ "$START_EXISTS" = true ] && [ "$END_EXISTS" = true ] && [ "$PRECOMPACT_EXISTS" = true ]; then
    echo "Hooks already installed, skipping hook configuration."
  else
    # Add missing hooks
    if [ "$START_EXISTS" = false ]; then
      TRACKER_START_HOOK=$(jq '.hooks.SessionStart[0]' "$HOOKS_CONFIG_PROCESSED")
      if jq -e '.hooks.SessionStart' "$SETTINGS_FILE" > /dev/null 2>&1; then
        jq --argjson start "$TRACKER_START_HOOK" '.hooks.SessionStart += [$start]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        jq --argjson start "$TRACKER_START_HOOK" '.hooks.SessionStart = [$start]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      fi
    fi

    if [ "$END_EXISTS" = false ]; then
      TRACKER_END_HOOK=$(jq '.hooks.SessionEnd[0]' "$HOOKS_CONFIG_PROCESSED")
      if jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" > /dev/null 2>&1; then
        jq --argjson end "$TRACKER_END_HOOK" '.hooks.SessionEnd += [$end]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        jq --argjson end "$TRACKER_END_HOOK" '.hooks.SessionEnd = [$end]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      fi
    fi

    if [ "$PRECOMPACT_EXISTS" = false ]; then
      TRACKER_PRECOMPACT_HOOK=$(jq '.hooks.PreCompact[0]' "$HOOKS_CONFIG_PROCESSED")
      if jq -e '.hooks.PreCompact' "$SETTINGS_FILE" > /dev/null 2>&1; then
        jq --argjson precompact "$TRACKER_PRECOMPACT_HOOK" '.hooks.PreCompact += [$precompact]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        jq --argjson precompact "$TRACKER_PRECOMPACT_HOOK" '.hooks.PreCompact = [$precompact]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      fi
    fi
  fi

  #######################################
  # Add permissions to protect hooks from modification
  #######################################
  HOOK_PERMISSIONS=$(jq '.permissions.deny // []' "$HOOKS_CONFIG_PROCESSED")

  # Merge with existing permissions (avoid duplicates)
  if jq -e '.permissions.deny' "$SETTINGS_FILE" > /dev/null 2>&1; then
    # Append our permissions if not already present
    jq --argjson new_perms "$HOOK_PERMISSIONS" \
      '.permissions.deny = (.permissions.deny + $new_perms | unique)' \
      "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  else
    # No existing permissions, add ours
    jq --argjson new_perms "$HOOK_PERMISSIONS" \
      '.permissions.deny = $new_perms' \
      "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  fi
else
  # No existing settings, copy hooks config
  cp "$HOOKS_CONFIG_PROCESSED" "$SETTINGS_FILE"
fi

#######################################
# Check for .gitignore issues
# Claude Code may add .claude to gitignore, which breaks hooks
#######################################
check_gitignore_issues() {
  local project_dir="$1"
  local gitignore_file="$project_dir/.gitignore"
  local issues_found=false

  if [ ! -f "$gitignore_file" ]; then
    return 0
  fi

  # Patterns that would break Claude Logger
  local critical_patterns=(
    "^\.claude/?$"           # .claude or .claude/
    "^\.claude/\*$"          # .claude/*
    "^\.claude/settings"     # .claude/settings.json
    "^\.claude/hooks"        # .claude/hooks
    "^\.claude/sessions"     # .claude/sessions
  )

  echo ""
  echo "Checking .gitignore for conflicts..."

  for pattern in "${critical_patterns[@]}"; do
    if grep -qE "$pattern" "$gitignore_file" 2>/dev/null; then
      if [ "$issues_found" = false ]; then
        echo ""
        echo "⚠️  WARNING: Critical files are in .gitignore!"
        echo "   Claude Logger will NOT work correctly."
        echo ""
        issues_found=true
      fi
      local matched_line=$(grep -E "$pattern" "$gitignore_file" | head -1)
      echo "   PROBLEM: '$matched_line' in .gitignore"
    fi
  done

  if [ "$issues_found" = true ]; then
    echo ""
    echo "   These files MUST NOT be gitignored:"
    echo "   - .claude/settings.json (tells Claude Code to run hooks)"
    echo "   - .claude/hooks/ (the hook scripts)"
    echo "   - .claude/sessions/ (session tracking data)"
    echo ""
    echo "   To fix, edit $gitignore_file and remove or modify these patterns."
    echo ""
  fi

  if [ "$issues_found" = true ]; then
    return 1
  fi
  return 0
}

# Run gitignore check (skip for global mode)
GITIGNORE_OK=true
if [ "$GLOBAL_MODE" = false ] && [ -n "$PROJECT_DIR" ]; then
  if ! check_gitignore_issues "$PROJECT_DIR"; then
    GITIGNORE_OK=false
  fi
fi

echo ""
echo "Claude Tracker installed successfully!"
echo ""

if [ "$GITIGNORE_OK" = false ]; then
  echo "⚠️  ACTION REQUIRED: Fix .gitignore issues above before using Claude Logger."
  echo ""
fi

if [ "$NICKNAME_FROM_ENV" = false ]; then
  echo "IMPORTANT: Add this to your shell profile (.bashrc, .zshrc, etc.):"
  echo ""
  echo "  export CLAUDE_LOGGER_USER=\"$CLAUDE_LOGGER_USER\""
  echo ""
fi

if [ "$GLOBAL_MODE" = true ]; then
  echo "Session data will be saved to: $HOME/.claude-logger/sessions/$CLAUDE_LOGGER_USER/"
else
  echo "Session data will be saved to: $PROJECT_DIR/.claude/sessions/$CLAUDE_LOGGER_USER/"
fi
echo ""
