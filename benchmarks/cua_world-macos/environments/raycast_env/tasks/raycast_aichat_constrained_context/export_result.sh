#!/bin/bash
# Export: raycast_aichat_constrained_context

set -euo pipefail
echo "=== Export: raycast_aichat_constrained_context ==="

RESULT_FILE="/tmp/raycast_aichat_constrained_context_result.json"
START_TS=$(cat /tmp/raycast_aichat_constrained_context_start_ts 2>/dev/null || echo "0")
INITIAL_NOTE_LEN=$(cat /tmp/raycast_aichat_constrained_context_initial_note_len 2>/dev/null || echo "0")

# Read 'Packing constraints' Note + total count of notes
NOTE_BODY=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Notes"
    try
        repeat with n in notes
            if name of n is "Packing constraints" then
                return body of n
            end if
        end repeat
        return ""
    end try
end tell
APPLEOF
)

# Count notes whose name contains 'Trip conflict' or 'Conflict check'
NEW_NOTE_COUNT=$(osascript << 'APPLEOF' 2>/dev/null || echo "0"
tell application "Notes"
    try
        set c to 0
        repeat with n in notes
            set nm to name of n as text
            if nm contains "Trip conflict" or nm contains "Conflict check" then
                set c to c + 1
            end if
        end repeat
        return c as text
    on error
        return "0"
    end try
end tell
APPLEOF
)

# Raycast WAL
RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
WAL_MTIME=$(stat -f%m "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

export NOTE_BODY_ENV="$NOTE_BODY"

python3 - "$RESULT_FILE" "$START_TS" "$INITIAL_NOTE_LEN" "$NEW_NOTE_COUNT" "$WAL_MTIME" << 'PYEOF'
import json, os, sys, re

result_file, start_ts, init_len, new_note_count, wal_mtime = sys.argv[1:6]
note_body = os.environ.get("NOTE_BODY_ENV", "")
note_plain = re.sub(r"<[^>]+>", "\n", note_body)
note_plain = re.sub(r"[ \t]+", " ", note_plain).strip()

result = {
    "task_start":            int(start_ts),
    "initial_note_length":   int(init_len),
    "note_body_raw":         note_body,
    "note_body_plain":       note_plain,
    "note_body_length":      len(note_body),
    "note_grew":             len(note_body) > int(init_len),
    "new_note_count":        int(new_note_count.strip() or "0"),
    "raycast_wal_mtime":     int(wal_mtime),
    "raycast_wal_changed_after_setup": int(wal_mtime) > int(start_ts),
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: note_grew={result['note_grew']} extra_notes={result['new_note_count']}")
PYEOF

echo "=== Export complete ==="
