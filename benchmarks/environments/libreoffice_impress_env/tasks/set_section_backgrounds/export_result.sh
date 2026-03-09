#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Set Section Backgrounds Result ==="

# Path to the expected file
PRESENTATION_FILE="/home/ga/Documents/Presentations/QBR_Q3_2024.odp"

# Take final screenshot BEFORE closing anything
take_screenshot /tmp/task_final.png

# Check if file exists and gather stats
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$PRESENTATION_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PRESENTATION_FILE")
    FILE_MTIME=$(stat -c %Y "$PRESENTATION_FILE")
fi

# Check timestamps against start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ] && [ "$FILE_MTIME" -gt "$INITIAL_MTIME" ]; then
    FILE_MODIFIED="true"
fi

# Create result JSON
cat << EOF > /tmp/task_result.json
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$PRESENTATION_FILE",
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "task_start_time": $TASK_START,
    "file_mtime": $FILE_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="