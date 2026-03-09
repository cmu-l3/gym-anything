#!/bin/bash
set -e

echo "=== Exporting compile_aircraft_dossier results ==="

source /workspace/scripts/task_utils.sh

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/aircraft_dossier.txt"
GROUND_TRUTH_PATH="/tmp/aircraft_ground_truth.json"

# Capture final state
take_screenshot /tmp/task_final.png

# Check report file status
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Load ground truth
GROUND_TRUTH_CONTENT="{}"
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GROUND_TRUTH_CONTENT=$(cat "$GROUND_TRUTH_PATH")
fi

# Check if browser is running
BROWSER_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    BROWSER_RUNNING="true"
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "browser_running": $BROWSER_RUNNING,
    "report_content_b64": "$REPORT_CONTENT",
    "ground_truth": $GROUND_TRUTH_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"