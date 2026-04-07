#!/bin/bash
set -euo pipefail

echo "=== Exporting AS/RS Crane Linear Kinematics result ==="

export DISPLAY=${DISPLAY:-:1}

# Take final screenshot
scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Desktop/asrs_configured.wbt"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Write metadata JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "output_path": "$OUTPUT_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="