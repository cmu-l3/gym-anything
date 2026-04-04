#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Forensic Identification Result ==="

REPORT_PATH="/home/ga/Evidence/forensic_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if report exists and read content
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0) # Base64 encode to safely pass in JSON
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# 2. Check for leftover mounts
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
LEFT_MOUNTED="false"
if echo "$MOUNT_LIST" | grep -q "^[0-9]"; then
    LEFT_MOUNTED="true"
fi

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
# Using python to create JSON avoids escaping hell with bash strings
python3 -c "
import json
import os
import time

result = {
    'report_exists': $REPORT_EXISTS,
    'report_content_b64': '$REPORT_CONTENT',
    'report_mtime': $REPORT_MTIME,
    'task_start_time': $TASK_START,
    'left_mounted': $LEFT_MOUNTED,
    'timestamp': time.time()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions for the result file
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="