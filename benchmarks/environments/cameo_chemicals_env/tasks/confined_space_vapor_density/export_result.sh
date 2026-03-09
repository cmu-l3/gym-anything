#!/bin/bash
echo "=== Exporting Confined Space Vapor Density Assessment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Define output path
REPORT_PATH="/home/ga/Documents/confined_space_vapor_report.txt"

# Check report file status
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content (safely, handling potential binary data or massive files)
    # Using base64 to ensure safe JSON embedding, or just raw text if small
    if [ "$REPORT_SIZE" -lt 10000 ]; then
        REPORT_CONTENT=$(cat "$REPORT_PATH")
    else
        REPORT_CONTENT="[File too large]"
    fi
fi

# Check if Firefox is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
# Note: Using python to safely dump JSON including the file content
python3 -c "
import json
import os
import sys

try:
    content = '''$REPORT_CONTENT'''
except:
    content = ''

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'report_exists': $REPORT_EXISTS == 'true',
    'report_created_during_task': $REPORT_CREATED_DURING_TASK == 'true',
    'report_size': int('$REPORT_SIZE'),
    'report_content': content,
    'app_running': $APP_RUNNING == 'true',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions so host can read it easily if needed (though copy_from_env handles root)
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="