# ENT-46: Transfer Conversation Transcripts to Project

## Problem

Claude Code saves conversation transcripts to `~/.claude/projects/{encoded-path}/{session_id}.jsonl` on the user's local machine. These files:
- Are not part of the project repository
- Cannot be shared with team members
- Are lost if the user's machine is wiped
- Are separate from our session enrichment data

## Solution

Copy the transcript file to `.claude/sessions/{nickname}/{session_id}.jsonl` at session end, alongside the existing enrichment JSON file.

## Current State

```
~/.claude/projects/{encoded-path}/
├── {session_id}.jsonl          # Claude Code transcript (user-local)

.claude/sessions/{nickname}/
├── {session_id}.json           # Our enrichment data (project-local)
```

## Target State

```
.claude/sessions/{nickname}/
├── {session_id}.json           # Enrichment data (unchanged)
├── {session_id}.jsonl          # Copied transcript
```

## Implementation

### Modify `hooks/session_end.sh`

Add transcript copy after updating the session JSON:

```bash
# Copy transcript to project-local sessions directory
copy_transcript() {
  local transcript_path="$1"
  local session_id="$2"
  local dest_dir="$3"

  if [ -f "$transcript_path" ]; then
    # Copy transcript alongside the session JSON
    cp "$transcript_path" "$dest_dir/${session_id}.jsonl"
  fi
}
```

### Changes Required

1. **session_end.sh** - Add transcript copy logic:
   - Read transcript_path from the existing session JSON
   - Copy the file to the sessions directory
   - Handle missing/empty transcripts gracefully

2. **No changes needed to session_start.sh** - It already captures `transcript_path`

### Edge Cases

| Case | Handling |
|------|----------|
| Transcript file doesn't exist | Skip copy, log nothing (graceful) |
| Transcript file is empty (0 bytes) | Skip copy |
| Transcript file is very large (>10MB) | Copy anyway (user's choice to commit) |
| Permission denied | Skip copy (graceful failure) |
| Session JSON missing transcript_path | Skip copy |

### File Size Considerations

Observed transcript sizes:
- Empty: 0 bytes (aborted sessions)
- Small: 261 bytes - 2KB (quick sessions)
- Medium: 200KB - 1MB (typical sessions)
- Large: 1MB - 4MB+ (long sessions)

Users can choose whether to commit transcripts to git. The `.gitignore` check will NOT warn about ignoring `.jsonl` files specifically, only the directory.

## Testing

Add tests to `hooks/tests/test_session_end.sh`:

1. Transcript copied when present
2. Graceful skip when transcript missing
3. Graceful skip when transcript empty
4. Correct destination path

## Rollout

1. Update session_end.sh
2. Add tests
3. Update documentation
4. Users get transcripts automatically on next session end
