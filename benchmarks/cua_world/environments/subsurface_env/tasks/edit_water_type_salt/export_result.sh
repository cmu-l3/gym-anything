#!/bin/bash
set -e
echo "=== Exporting edit_water_type_salt task result ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SSRF_PATH="/home/ga/Documents/dives.ssrf"
INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"
CURRENT_MTIME="0"

if [ -f "$SSRF_PATH" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c%Y "$SSRF_PATH" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c%s "$SSRF_PATH" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if Subsurface is still running
APP_RUNNING="false"
if pgrep -f "subsurface" > /dev/null; then
    APP_RUNNING="true"
fi

# Export metadata JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

# Safely move json to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="