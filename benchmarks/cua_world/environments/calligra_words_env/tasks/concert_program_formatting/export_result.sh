#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Concert Program Formatting Result ==="

# Focus window and take final screenshot
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi
take_screenshot /tmp/calligra_concert_program_formatting_post_task.png

# Gather file metrics for anti-gaming checks
FILE_PATH="/home/ga/Documents/concert_program.odt"
if [ -f "$FILE_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo 0)
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo 0)
else
    FILE_MTIME=0
    FILE_SIZE=0
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

# Export metrics to JSON
cat > /tmp/task_result.json << EOF
{
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/calligra_concert_program_formatting_post_task.png"
}
EOF
chmod 666 /tmp/task_result.json

# Close Calligra gracefully so the agent's work isn't corrupted
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="