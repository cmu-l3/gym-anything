#!/bin/bash
# Export: raycast_screenshot_ocr_aichat

set -euo pipefail
echo "=== Export: raycast_screenshot_ocr_aichat ==="

RESULT_FILE="/tmp/raycast_screenshot_ocr_aichat_result.json"
START_TS=$(cat /tmp/raycast_screenshot_ocr_aichat_start_ts 2>/dev/null || echo "0")

NOTE_BODY=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Notes"
    try
        repeat with n in notes
            if name of n is "Packages" then
                return body of n
            end if
        end repeat
        return ""
    end try
end tell
APPLEOF
)

RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
WAL_MTIME=$(stat -f%m "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

export NOTE_BODY_ENV="$NOTE_BODY"

python3 - "$RESULT_FILE" "$START_TS" "$WAL_MTIME" << 'PYEOF'
import json, os, sys, re

result_file, start_ts, wal_mtime = sys.argv[1:4]
body = os.environ.get("NOTE_BODY_ENV", "")
plain = re.sub(r"<[^>]+>", "\n", body)
plain = re.sub(r"[ \t]+", " ", plain).strip()

result = {
    "task_start":             int(start_ts),
    "note_exists":            bool(body),
    "note_body_raw":          body,
    "note_body_plain":        plain,
    "raycast_wal_mtime":      int(wal_mtime),
    "raycast_wal_changed_after_setup": int(wal_mtime) > int(start_ts),
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: note_exists={bool(body)} plain={plain[:80]!r}")
PYEOF

echo "=== Export complete ==="
