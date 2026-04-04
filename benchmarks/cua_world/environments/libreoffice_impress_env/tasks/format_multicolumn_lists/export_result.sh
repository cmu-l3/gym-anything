#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

FILE_PATH="/home/ga/Documents/Presentations/gala_sponsors.odp"

# Focus window to ensure inputs work
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Attempt to save in case the agent forgot (gentle helper, though instructions say save)
# We don't want to fail just because they didn't press Ctrl+S at the very end if the work is done
# But verify modification time to distinguish.
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture file stats
if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
else
    FILE_EXISTS="false"
    FILE_SIZE=0
    FILE_MTIME=0
fi

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")

# Determine if modified
WAS_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$INITIAL_MTIME" ]; then
    WAS_MODIFIED="true"
fi

# Create export JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$FILE_PATH",
    "was_modified": $WAS_MODIFIED,
    "start_time": $START_TIME,
    "final_mtime": $FILE_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json