#!/bin/bash
set -euo pipefail

echo "=== Exporting enrich_dive_site_taxonomy result ==="

export DISPLAY="${DISPLAY:-:1}"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check Subsurface status
APP_RUNNING="false"
if pgrep -f "subsurface" > /dev/null; then
    APP_RUNNING="true"
fi

# Check Output file
SSRF_PATH="/home/ga/Documents/dives.ssrf"
FILE_EXISTS="false"
FILE_MTIME="0"
FILE_SIZE="0"

if [ -f "$SSRF_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$SSRF_PATH")
    FILE_SIZE=$(stat -c%s "$SSRF_PATH")
fi

# Determine if modified
FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$INITIAL_MTIME" ]; then
    FILE_MODIFIED="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_mtime": $INITIAL_MTIME,
    "file_mtime": $FILE_MTIME,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="