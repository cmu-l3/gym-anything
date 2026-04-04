#!/bin/bash
echo "=== Exporting regression diagnostics results ==="

# 1. Record end time and read start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check for JASP project file
JASP_FILE="/home/ga/Documents/JASP/RegressionDiagnostics.jasp"
JASP_EXISTS="false"
JASP_SIZE=0
JASP_MODIFIED="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c%Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_MODIFIED="true"
    fi
fi

# 3. Check for Report file
REPORT_FILE="/home/ga/Documents/JASP/diagnostics_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MODIFIED="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
    # Read content (base64 encode to safely put in JSON, or just raw if simple text)
    # We'll use raw text but escaped
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 1000) 
fi

# 4. Check if JASP is still running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 5. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create JSON result
# Python is safer for JSON generation to handle escaping
python3 -c "
import json
import os
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'jasp_file_exists': $JASP_EXISTS,
    'jasp_file_size': $JASP_SIZE,
    'jasp_file_created_during_task': $JASP_MODIFIED,
    'report_file_exists': $REPORT_EXISTS,
    'report_file_created_during_task': $REPORT_MODIFIED,
    'report_content': '''$REPORT_CONTENT''',
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 7. Move output to safe location for verifier
# (The framework uses copy_from_env on /tmp/task_result.json directly, 
# but ensuring permissions is good practice)
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json