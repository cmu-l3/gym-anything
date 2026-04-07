#!/bin/bash
set -euo pipefail
echo "=== Exporting Genomics Lab Browser Hardening task result ==="

# 1. Take final screenshot before altering state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Safely close Chrome to flush Preferences/Bookmarks/Local State to disk
echo "Closing Chrome to flush configurations to disk..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true

# 3. Collect timestamps for anti-gaming verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to get mtime safely
get_mtime() {
    stat -c %Y "$1" 2>/dev/null || echo "0"
}

PREFS_PATH="/home/ga/.config/google-chrome-cdp/Default/Preferences"
BM_PATH="/home/ga/.config/google-chrome-cdp/Default/Bookmarks"
STATE_PATH="/home/ga/.config/google-chrome-cdp/Local State"

PREFS_MTIME=$(get_mtime "$PREFS_PATH")
BM_MTIME=$(get_mtime "$BM_PATH")
STATE_MTIME=$(get_mtime "$STATE_PATH")

# 4. Generate JSON result map
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "preferences_mtime": $PREFS_MTIME,
    "bookmarks_mtime": $BM_MTIME,
    "local_state_mtime": $STATE_MTIME,
    "files_exist": {
        "preferences": $([ -f "$PREFS_PATH" ] && echo "true" || echo "false"),
        "bookmarks": $([ -f "$BM_PATH" ] && echo "true" || echo "false"),
        "local_state": $([ -f "$STATE_PATH" ] && echo "true" || echo "false")
    }
}
EOF

rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Task metadata extracted to /tmp/task_result.json"
echo "=== Export complete ==="