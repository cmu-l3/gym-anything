#!/bin/bash
echo "=== Exporting ordinal_regression_bigfive results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

JASP_FILE="/home/ga/Documents/JASP/Ordinal_A1_Analysis.jasp"
REPORT_FILE="/home/ga/Documents/JASP/ordinal_report.txt"

# 1. Check JASP file
JASP_EXISTS="false"
JASP_CREATED_DURING="false"
JASP_SIZE="0"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# 2. Check Report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    # Read content (safe read)
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 20)
fi

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Bundle into JSON
# Using python to safely escape JSON strings
python3 -c "
import json
import os
import time

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'jasp_file': {
        'exists': $JASP_EXISTS,
        'created_during_task': $JASP_CREATED_DURING,
        'size_bytes': $JASP_SIZE,
        'path': '$JASP_FILE'
    },
    'report_file': {
        'exists': $REPORT_EXISTS,
        'created_during_task': $REPORT_CREATED_DURING,
        'content': '''$REPORT_CONTENT'''
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions so verifier can copy it
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="