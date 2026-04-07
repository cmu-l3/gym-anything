#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check Subsurface file state
FILE_PATH="/home/ga/Documents/dives.ssrf"
FILE_EXISTS="false"
FILE_MODIFIED="false"
CURRENT_MTIME="0"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c%Y "$FILE_PATH")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="