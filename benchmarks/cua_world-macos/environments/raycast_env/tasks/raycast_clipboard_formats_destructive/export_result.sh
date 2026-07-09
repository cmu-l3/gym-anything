#!/bin/bash
# Export: raycast_clipboard_formats_destructive

set -euo pipefail
echo "=== Export: raycast_clipboard_formats_destructive ==="

RESULT_FILE="/tmp/raycast_clipboard_formats_destructive_result.json"
START_TS=$(cat /tmp/raycast_clipboard_formats_destructive_start_ts 2>/dev/null || echo "0")
INBOX="/Users/lume/Desktop/Household Inbox"

# --- 1. Final system clipboard value (must be 'call mom after 6') ---
CLIPBOARD_FINAL=$(pbpaste 2>/dev/null || echo "")

# --- 2. Read Mail draft content ---
MAIL_DRAFT_CONTENT=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Mail"
    try
        set out to ""
        repeat with msg in outgoing messages
            if (subject of msg) contains "May 2026 newsletter" then
                set out to content of msg
                exit repeat
            end if
        end repeat
        return out
    on error
        return ""
    end try
end tell
APPLEOF
)

# --- 3. Inspect ~/Desktop/Household Inbox contents ---
INBOX_LISTING=$(ls -la "$INBOX" 2>/dev/null || echo "MISSING_DIR")

# --- 4. Best-effort Raycast WAL signal ---
RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
WAL_SIZE=$(stat -f%z "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")
WAL_MTIME=$(stat -f%m "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

# --- 5. Assemble JSON ---
export MAIL_DRAFT_CONTENT_FROM_ENV="$MAIL_DRAFT_CONTENT"
export CLIPBOARD_FINAL_FROM_ENV="$CLIPBOARD_FINAL"
export INBOX_LISTING_FROM_ENV="$INBOX_LISTING"

python3 - "$RESULT_FILE" "$START_TS" "$INBOX" "$WAL_SIZE" "$WAL_MTIME" << 'PYEOF'
import json, os, sys, pathlib

result_file, start_ts, inbox, wal_size, wal_mtime = sys.argv[1:6]
mail_content = os.environ.get("MAIL_DRAFT_CONTENT_FROM_ENV", "")
clipboard_final = os.environ.get("CLIPBOARD_FINAL_FROM_ENV", "")
inbox_listing = os.environ.get("INBOX_LISTING_FROM_ENV", "")

inbox_path = pathlib.Path(inbox)
inbox_files = []
if inbox_path.is_dir():
    for f in inbox_path.iterdir():
        try:
            st = f.stat()
            inbox_files.append({
                "name": f.name,
                "size_bytes": st.st_size,
                "mtime": int(st.st_mtime),
                "is_new": st.st_mtime > int(start_ts),
            })
        except Exception:
            pass

result = {
    "task_start":            int(start_ts),
    "final_clipboard":       clipboard_final,
    "mail_draft_content":    mail_content,
    "mail_draft_length":     len(mail_content),
    "inbox_path":            str(inbox_path),
    "inbox_exists":          inbox_path.is_dir(),
    "inbox_files":           inbox_files,
    "inbox_file_count":      len(inbox_files),
    "inbox_listing_raw":     inbox_listing,
    "raycast_wal_size_bytes":          int(wal_size),
    "raycast_wal_mtime":               int(wal_mtime),
    "raycast_wal_changed_after_setup": int(wal_mtime) > int(start_ts),
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: clip='{clipboard_final[:40]}' mail_len={len(mail_content)} "
      f"inbox_files={len(inbox_files)}")
PYEOF

echo "=== Export complete ==="
