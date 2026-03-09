#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Annotate Dashboard Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Attempt to save the file gracefully
echo "Saving presentation..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Ctrl+S to save
safe_xdotool ga :1 key --delay 200 ctrl+s
sleep 2

# Check if file was updated
FILE_PATH="/home/ga/Documents/Presentations/revenue_analysis.odp"
FILE_UPDATED="false"
FILE_SIZE=0

if [ -f "$FILE_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_UPDATED="true"
        echo "✅ File was modified during task."
    else
        echo "⚠️ File exists but was not modified."
    fi
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
else
    echo "❌ File not found!"
fi

# 2. Take final screenshot for VLM verification
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $([ -f "$FILE_PATH" ] && echo "true" || echo "false"),
    "file_updated": $FILE_UPDATED,
    "file_path": "$FILE_PATH",
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json