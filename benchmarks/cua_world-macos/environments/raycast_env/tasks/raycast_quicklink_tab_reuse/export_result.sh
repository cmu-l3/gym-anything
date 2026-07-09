#!/bin/bash
# Export: raycast_quicklink_tab_reuse

set -euo pipefail
echo "=== Export: raycast_quicklink_tab_reuse ==="

RESULT_FILE="/tmp/raycast_quicklink_tab_reuse_result.json"
START_TS=$(cat /tmp/raycast_quicklink_tab_reuse_start_ts 2>/dev/null || echo "0")
EXPORT_FILE="/Users/lume/Desktop/my_quicklinks.json"

# --- 1. Count Safari tabs and get URLs ---
SAFARI_TAB_URLS=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Safari"
    try
        set out to ""
        repeat with w in windows
            repeat with t in tabs of w
                set out to out & (URL of t) & linefeed
            end repeat
        end repeat
        return out
    on error
        return ""
    end try
end tell
APPLEOF
)
TAB_COUNT=$(echo "$SAFARI_TAB_URLS" | grep -c "^http" 2>/dev/null || echo "0")

# --- 2. Parse Quicklinks export ---
EXPORT_EXISTS="false"
EXPORT_NEW="false"
EXPORT_CONTENT="[]"
if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_MTIME=$(stat -f%m "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$EXPORT_MTIME" -gt "$START_TS" ]; then EXPORT_NEW="true"; fi
    EXPORT_CONTENT=$(cat "$EXPORT_FILE" 2>/dev/null || echo "[]")
fi

# --- 3. Raycast WAL ---
RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
WAL_MTIME=$(stat -f%m "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

# --- Assemble JSON ---
export SAFARI_TAB_URLS_ENV="$SAFARI_TAB_URLS"
export EXPORT_CONTENT_ENV="$EXPORT_CONTENT"

python3 - "$RESULT_FILE" "$START_TS" "$TAB_COUNT" "$EXPORT_EXISTS" "$EXPORT_NEW" "$WAL_MTIME" << 'PYEOF'
import json, os, sys

result_file, start_ts, tab_count, export_exists, export_new, wal_mtime = sys.argv[1:7]
tab_urls_raw = os.environ.get("SAFARI_TAB_URLS_ENV", "")
export_content_raw = os.environ.get("EXPORT_CONTENT_ENV", "[]")

tab_urls = [u.strip() for u in tab_urls_raw.splitlines() if u.strip().startswith("http")]

quicklinks = []
try:
    data = json.loads(export_content_raw)
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict) and "quicklinks" in data:
        items = data["quicklinks"]
    else:
        items = []
    for it in items:
        if isinstance(it, dict):
            quicklinks.append({
                "name": str(it.get("name") or it.get("title") or ""),
                "link": str(it.get("link") or it.get("url") or ""),
                "description": str(it.get("description") or ""),
            })
except (json.JSONDecodeError, Exception):
    pass

result = {
    "task_start":         int(start_ts),
    "safari_tab_urls":    tab_urls,
    "safari_tab_count":   len(tab_urls),
    "export_file_exists": export_exists.strip() == "true",
    "export_file_is_new": export_new.strip() == "true",
    "quicklinks":         quicklinks,
    "quicklink_count":    len(quicklinks),
    "raycast_wal_mtime":  int(wal_mtime),
    "raycast_wal_changed_after_setup": int(wal_mtime) > int(start_ts),
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: tabs={len(tab_urls)} quicklinks={len(quicklinks)}")
PYEOF

echo "=== Export complete ==="
