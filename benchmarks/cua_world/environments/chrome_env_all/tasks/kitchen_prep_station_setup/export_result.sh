#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Kitchen Prep Station Configuration Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush Preferences, Bookmarks, and Web Data to disk
echo "Closing Chrome to flush SQLite and JSON data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Extract timestamps to verify agent actively changed things
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
PREFS_MTIME=$(stat -c %Y "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "0")
BKMKS_MTIME=$(stat -c %Y "$CHROME_PROFILE/Bookmarks" 2>/dev/null || echo "0")
WEBDATA_MTIME=$(stat -c %Y "$CHROME_PROFILE/Web Data" 2>/dev/null || echo "0")

# Create JSON result for easy parsing by verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_mtime": $PREFS_MTIME,
    "bookmarks_mtime": $BKMKS_MTIME,
    "webdata_mtime": $WEBDATA_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Data exported and Chrome flushed."
echo "=== Export complete ==="