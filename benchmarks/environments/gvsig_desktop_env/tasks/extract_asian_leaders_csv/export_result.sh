#!/bin/bash
echo "=== Exporting extract_asian_leaders_csv results ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_FILE="/home/ga/gvsig_data/exports/asian_leaders.csv"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Get task start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# 1. Check Output File
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Application State
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Generate Result JSON
# We use Python to generate valid JSON safely
python3 << EOF > "$RESULT_JSON"
import json
import os

result = {
    "output_file_path": "$OUTPUT_FILE",
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}

with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=4)
EOF

# Ensure permissions for the verifier to read
chmod 644 "$RESULT_JSON"
chmod 644 /tmp/task_final.png 2>/dev/null || true
if [ -f "$OUTPUT_FILE" ]; then
    chmod 644 "$OUTPUT_FILE"
fi

echo "Export complete. Result JSON:"
cat "$RESULT_JSON"