#!/bin/bash
# Export script for SERP Mode Visualization task
source /workspace/scripts/task_utils.sh

echo "=== Exporting SERP Mode Task Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define variables
EXPORT_DIR="/home/ga/Documents/SEO/exports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
RESULT_FILE="/tmp/task_result.json"

# 3. Find the most relevant export file
# We look for a CSV created AFTER task start
NEWEST_CSV=""
NEWEST_EPOCH=0

if [ -d "$EXPORT_DIR" ]; then
    # Iterate over all CSVs to find the newest valid one
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            if [ "$FILE_EPOCH" -gt "$NEWEST_EPOCH" ]; then
                NEWEST_CSV="$csv_file"
                NEWEST_EPOCH="$FILE_EPOCH"
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 4. Analyze the file (if found)
FILE_FOUND="false"
FILE_SIZE_BYTES=0
EXPORTED_FILE_PATH=""

if [ -n "$NEWEST_CSV" ]; then
    FILE_FOUND="true"
    EXPORTED_FILE_PATH="$NEWEST_CSV"
    FILE_SIZE_BYTES=$(stat -c %s "$NEWEST_CSV" 2>/dev/null || echo "0")
    
    # Copy for verification
    cp "$NEWEST_CSV" /tmp/exported_serp_data.csv
fi

# 5. Check if App is running
APP_RUNNING="false"
if is_screamingfrog_running; then
    APP_RUNNING="true"
fi

# 6. Capture Window Title (to check for "Mode: SERP" if visible)
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l | grep -i "screaming frog" | head -1 | sed 's/"/\\"/g')

# 7. Create JSON result
# Use Python to generate valid JSON safely
python3 << EOF
import json
import os
import time

result = {
    "task_start_epoch": $TASK_START_EPOCH,
    "task_end_epoch": int(time.time()),
    "file_found": $FILE_FOUND,
    "exported_file_path": "$EXPORTED_FILE_PATH",
    "file_size_bytes": $FILE_SIZE_BYTES,
    "app_running": $APP_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "screenshot_path": "/tmp/task_final.png"
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=4)
EOF

# Ensure permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true
chmod 666 /tmp/exported_serp_data.csv 2>/dev/null || true

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="