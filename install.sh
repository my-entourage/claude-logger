#!/bin/bash
set -euo pipefail

echo "Installing Claude Tracker..."

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

#######################################
# Prompt for GitHub nickname (blocking with validation)
#######################################
echo ""
echo "Claude Tracker requires a nickname to organize your sessions."
echo "This should be your GitHub username or a consistent identifier."
echo "(Valid: 1-39 characters, lowercase letters, numbers, dashes, underscores)"
echo ""

GITHUB_NICKNAME=""
while true; do
  read -p "Enter your nickname: " GITHUB_NICKNAME

  # Normalize to lowercase
  GITHUB_NICKNAME=$(echo "$GITHUB_NICKNAME" | tr '[:upper:]' '[:lower:]')

  if [ -z "$GITHUB_NICKNAME" ]; then
    echo "Error: Nickname cannot be empty. Please try again."
    continue
  fi

  if validate_nickname "$GITHUB_NICKNAME"; then
    break
  else
    echo "Error: Invalid nickname '$GITHUB_NICKNAME'."
    echo "Must be 1-39 characters, lowercase alphanumeric with dashes/underscores only."
    echo "Please try again."
  fi
done

echo ""
echo "Using nickname: $GITHUB_NICKNAME"

# Create directories
mkdir -p "$PROJECT_DIR/.claude/hooks"

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

  # Check for duplicate hooks before adding
  START_EXISTS=false
  END_EXISTS=false

  if hook_exists "$SETTINGS_FILE" "SessionStart" "session_start.sh"; then
    START_EXISTS=true
    echo "Note: SessionStart hook already configured, skipping..."
  fi

  if hook_exists "$SETTINGS_FILE" "SessionEnd" "session_end.sh"; then
    END_EXISTS=true
    echo "Note: SessionEnd hook already configured, skipping..."
  fi

  if [ "$START_EXISTS" = true ] && [ "$END_EXISTS" = true ]; then
    echo "Hooks already installed, skipping hook configuration."
  elif [ "$START_EXISTS" = false ] && [ "$END_EXISTS" = false ]; then
    # Neither hook exists, check if hooks object exists
    if jq -e '.hooks.SessionStart' "$SETTINGS_FILE" > /dev/null 2>&1; then
      # Hooks array exists but doesn't contain our hooks, append
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
    # One exists but not the other - add the missing one
    if [ "$START_EXISTS" = false ]; then
      TRACKER_START_HOOK=$(jq '.hooks.SessionStart[0]' "$HOOKS_CONFIG")
      if jq -e '.hooks.SessionStart' "$SETTINGS_FILE" > /dev/null 2>&1; then
        jq --argjson start "$TRACKER_START_HOOK" '.hooks.SessionStart += [$start]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        jq --argjson start "$TRACKER_START_HOOK" '.hooks.SessionStart = [$start]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      fi
    fi
    if [ "$END_EXISTS" = false ]; then
      TRACKER_END_HOOK=$(jq '.hooks.SessionEnd[0]' "$HOOKS_CONFIG")
      if jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" > /dev/null 2>&1; then
        jq --argjson end "$TRACKER_END_HOOK" '.hooks.SessionEnd += [$end]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        jq --argjson end "$TRACKER_END_HOOK" '.hooks.SessionEnd = [$end]' \
          "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      fi
    fi
  fi
else
  # No existing settings, copy hooks config
  cp "$HOOKS_CONFIG" "$SETTINGS_FILE"
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
  )

  local warning_patterns=(
    "^\.claude/sessions"     # .claude/sessions - not critical but worth noting
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
    echo ""
    echo "   To fix, edit $gitignore_file and remove or modify these patterns."
    echo "   You can safely ignore .claude/sessions/ if you don't want to track session data."
    echo ""
  fi

  # Check for warning patterns (non-critical)
  for pattern in "${warning_patterns[@]}"; do
    if grep -qE "$pattern" "$gitignore_file" 2>/dev/null; then
      local matched_line=$(grep -E "$pattern" "$gitignore_file" | head -1)
      echo "   Note: '$matched_line' - sessions won't be committed (this is OK)"
    fi
  done

  if [ "$issues_found" = true ]; then
    return 1
  fi
  return 0
}

# Run gitignore check
GITIGNORE_OK=true
if ! check_gitignore_issues "$PROJECT_DIR"; then
  GITIGNORE_OK=false
fi

echo ""
echo "Claude Tracker installed successfully!"
echo ""

if [ "$GITIGNORE_OK" = false ]; then
  echo "⚠️  ACTION REQUIRED: Fix .gitignore issues above before using Claude Logger."
  echo ""
fi

echo "IMPORTANT: Add this to your shell profile (.bashrc, .zshrc, etc.):"
echo ""
echo "  export GITHUB_NICKNAME=\"$GITHUB_NICKNAME\""
echo ""
echo "Session data will be saved to: $PROJECT_DIR/.claude/sessions/$GITHUB_NICKNAME/"
echo "Sessions are automatically captured when GITHUB_NICKNAME is set."
echo ""
