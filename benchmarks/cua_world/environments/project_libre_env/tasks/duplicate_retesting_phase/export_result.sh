#!/bin/bash
echo "=== Exporting duplicate_retesting_phase results ==="

# Define paths
OUTPUT_FILE="/home/ga/Projects/extended_project.xml"
RESULT_JSON="/tmp/task_result.json"
TASK_START_FILE="/tmp/task_start_time.txt"

# Get task start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# Check output file status
FILE_EXISTS=false
FILE_SIZE=0
FILE_CREATED_DURING_TASK=false

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS=false
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS=true
fi

# Check if application is still running
APP_RUNNING=false
if pgrep -f "projectlibre" > /dev/null; then
    APP_RUNNING=true
fi

# Create JSON result
# Use a python script to generate clean JSON to avoid shell escaping issues
python3 -c "
import json
import os

result = {
    'file_exists': $FILE_EXISTS, # python will see True/False from bash lower case
    'file_size': $FILE_SIZE,
    'created_during_task': $FILE_CREATED_DURING_TASK,
    'app_running': $APP_RUNNING,
    'screenshot_exists': $SCREENSHOT_EXISTS,
    'output_path': '$OUTPUT_FILE'
}

# Python booleans are capitalized, bash are lower. 
# We need to ensure valid JSON.
# Actually, passing bash variables directly into python string like this is risky for booleans.
# Better to interpret strings:
" > /dev/null # Discard the python command start, let's do it cleanly:

cat <<EOF > /tmp/gen_json.py
import json
import sys

data = {
    "file_exists": "$FILE_EXISTS" == "true",
    "file_size": int("$FILE_SIZE"),
    "created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
    "app_running": "$APP_RUNNING" == "true",
    "screenshot_exists": "$SCREENSHOT_EXISTS" == "true",
    "output_path": "$OUTPUT_FILE"
}

with open("$RESULT_JSON", "w") as f:
    json.dump(data, f)
EOF

python3 /tmp/gen_json.py
rm /tmp/gen_json.py

# Set permissions so the host verifier can read it (via copy_from_env)
chmod 644 "$RESULT_JSON"
if [ -f "$OUTPUT_FILE" ]; then
    chmod 644 "$OUTPUT_FILE"
fi

echo "Export complete. Result:"
cat "$RESULT_JSON"