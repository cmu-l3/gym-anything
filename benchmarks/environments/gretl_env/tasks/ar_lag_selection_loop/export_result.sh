#!/bin/bash
echo "=== Exporting AR Lag Selection results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCRIPT_PATH="/home/ga/Documents/gretl_output/lag_screening.inp"
REPORT_PATH="/home/ga/Documents/gretl_output/lag_screening_report.txt"

# Check Script File
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read first few lines for debug (safely)
    REPORT_CONTENT=$(head -n 10 "$REPORT_PATH" | base64 -w 0)
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move results to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Also copy the actual files to /tmp for the verifier to read easily if needed
if [ -f "$SCRIPT_PATH" ]; then
    cp "$SCRIPT_PATH" /tmp/agent_script.inp
    chmod 666 /tmp/agent_script.inp
fi
if [ -f "$REPORT_PATH" ]; then
    cp "$REPORT_PATH" /tmp/agent_report.txt
    chmod 666 /tmp/agent_report.txt
fi

echo "=== Export complete ==="