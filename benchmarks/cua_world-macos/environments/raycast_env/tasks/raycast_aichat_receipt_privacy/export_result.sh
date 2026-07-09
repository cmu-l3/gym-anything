#!/bin/bash
# Export: raycast_aichat_receipt_privacy

set -euo pipefail
echo "=== Export: raycast_aichat_receipt_privacy ==="

RESULT_FILE="/tmp/raycast_aichat_receipt_privacy_result.json"
START_TS=$(cat /tmp/raycast_aichat_receipt_privacy_start_ts 2>/dev/null || echo "0")

# --- Read Apple Note 'Reimbursement subtotal' ---
NOTE_BODY=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Notes"
    try
        repeat with n in notes
            if name of n is "Reimbursement subtotal" then
                return body of n
            end if
        end repeat
        return ""
    on error
        return ""
    end try
end tell
APPLEOF
)

# --- Raycast WAL ---
RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
WAL_MTIME=$(stat -f%m "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

export NOTE_BODY_ENV="$NOTE_BODY"

python3 - "$RESULT_FILE" "$START_TS" "$WAL_MTIME" << 'PYEOF'
import json, os, sys, re

result_file, start_ts, wal_mtime = sys.argv[1:4]
note_body = os.environ.get("NOTE_BODY_ENV", "")
note_plain = re.sub(r"<[^>]+>", "\n", note_body)
note_plain = re.sub(r"\s+", " ", note_plain).strip()

result = {
    "task_start":            int(start_ts),
    "note_exists":           bool(note_body),
    "note_body_raw":         note_body,
    "note_body_plain":       note_plain,
    "raycast_wal_mtime":     int(wal_mtime),
    "raycast_wal_changed_after_setup": int(wal_mtime) > int(start_ts),
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: note_exists={bool(note_body)} plain={note_plain[:80]!r}")
PYEOF

echo "=== Export complete ==="
