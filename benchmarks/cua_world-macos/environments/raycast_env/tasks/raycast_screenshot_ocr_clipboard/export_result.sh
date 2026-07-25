#!/bin/bash
# Export: raycast_screenshot_ocr_clipboard

set -euo pipefail
echo "=== Export: raycast_screenshot_ocr_clipboard ==="

RESULT_FILE="/tmp/raycast_screenshot_ocr_clipboard_result.json"
START_TS=$(cat /tmp/raycast_screenshot_ocr_clipboard_start_ts 2>/dev/null || echo "0")

# --- 1. Final clipboard value ---
CLIPBOARD_FINAL=$(pbpaste 2>/dev/null || echo "")

# --- 2. Read Apple Notes body for 'Equipment Inventory' ---
NOTE_BODY=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Notes"
    try
        set output to ""
        repeat with n in notes
            if name of n is "Equipment Inventory" then
                set output to body of n
                exit repeat
            end if
        end repeat
        return output
    on error
        return ""
    end try
end tell
APPLEOF
)

# --- 3. Raycast WAL signal ---
RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
WAL_SIZE=$(stat -f%z "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")
WAL_MTIME=$(stat -f%m "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

# --- 4. Assemble JSON ---
export NOTE_BODY_ENV="$NOTE_BODY"
export CLIPBOARD_FINAL_ENV="$CLIPBOARD_FINAL"

python3 - "$RESULT_FILE" "$START_TS" "$WAL_SIZE" "$WAL_MTIME" << 'PYEOF'
import json, os, sys

result_file, start_ts, wal_size, wal_mtime = sys.argv[1:5]
note_body = os.environ.get("NOTE_BODY_ENV", "")
clipboard_final = os.environ.get("CLIPBOARD_FINAL_ENV", "")

# Apple Notes returns HTML-rich body. Strip simple tags for plain-text inspection.
import re
note_plain = re.sub(r"<[^>]+>", "\n", note_body)
note_plain = re.sub(r"\s+", " ", note_plain).strip()

result = {
    "task_start":       int(start_ts),
    "final_clipboard":  clipboard_final,
    "note_body_raw":    note_body,
    "note_body_plain":  note_plain,
    "raycast_wal_size_bytes":          int(wal_size),
    "raycast_wal_mtime":               int(wal_mtime),
    "raycast_wal_changed_after_setup": int(wal_mtime) > int(start_ts),
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: clip={clipboard_final!r} note_plain={note_plain[:80]!r}")
PYEOF

echo "=== Export complete ==="
