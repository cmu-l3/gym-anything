#!/bin/bash
echo "=== Exporting generate_case_bibliography_rtf result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Output File
OUTPUT_PATH="/home/ga/Documents/warren_bibliography.rtf"
FILE_EXISTS="false"
FILE_SIZE="0"
CREATED_DURING_TASK="false"
CONTENT_PREVIEW=""

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created/modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Read raw content (first 1000 chars) for JSON
    # RTF is text-based, so we can read it directly
    CONTENT_PREVIEW=$(head -c 1000 "$OUTPUT_PATH" | tr -d '\000' | sed 's/"/\\"/g' | tr '\n' ' ')
fi

# 4. Check App State
APP_RUNNING=$(pgrep -f "jurism" > /dev/null && echo "true" || echo "false")

# 5. Generate JSON Result
# Using a python script to safely create JSON and avoid quoting issues
python3 -c "
import json
import os
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': $FILE_EXISTS,
    'file_size': $FILE_SIZE,
    'created_during_task': $CREATED_DURING_TASK,
    'app_running': $APP_RUNNING,
    'content_preview': \"$CONTENT_PREVIEW\",
    'screenshot_path': '/tmp/task_final.png'
}

# Write to temp file
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Move to final location safely
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="