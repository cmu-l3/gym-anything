#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Risk Matrix Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/Presentations/project_status.odp"

# Focus Impress window to ensure keystrokes work
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Attempt to save via shortcut in case agent forgot
echo "Attempting safety save..."
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Check file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "target_path": "$TARGET_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="