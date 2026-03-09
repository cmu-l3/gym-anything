#!/bin/bash
echo "=== Exporting Security Config Audit results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
REPORT_PATH="/home/ga/security_audit.txt"
SCREENSHOT_PATH="/home/ga/security_options_screenshot.png"

# 1. Analyze Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT_PREVIEW=""
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read first 20 lines safely (encode to base64 to avoid JSON breaking chars, handled in python)
    # Here we just dump raw text for simplicity if it's clean, but let's just save existence for bash
    # and let verifier read the file via copy_from_env.
    # We will grab a grep check for keywords here just for basic debug logging
    echo "Report content preview:"
    head -n 5 "$REPORT_PATH"
fi

# 2. Analyze Screenshot File
SCREENSHOT_FILE_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_FILE_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture System State (Final Screenshot)
take_screenshot /tmp/task_final.png

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size": $REPORT_SIZE,
    "screenshot_file_exists": $SCREENSHOT_FILE_EXISTS,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "screenshot_size": $SCREENSHOT_SIZE,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="