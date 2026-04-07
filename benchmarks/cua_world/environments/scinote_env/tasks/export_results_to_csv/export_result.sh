#!/bin/bash
echo "=== Exporting export_results_to_csv task ==="

source /workspace/scripts/task_utils.sh

# Capture visual state
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/kinetics_data.csv"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Copy the file to /tmp so the verifier.py can safely access it via copy_from_env
    rm -f /tmp/kinetics_data.csv 2>/dev/null || true
    cp "$TARGET_FILE" /tmp/kinetics_data.csv
    chmod 666 /tmp/kinetics_data.csv
fi

# Export metadata 
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/export_task_result.json" "$RESULT_JSON"

echo "Export complete:"
cat /tmp/export_task_result.json