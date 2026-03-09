#!/bin/bash
# export_result.sh — Export results for Identify Power Anomaly task

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
REPORT_PATH="/home/ga/anomaly_report.txt"
GROUND_TRUTH_PATH="/var/lib/emoncms_ground_truth/anomaly_truth.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# Check User Report File
# -----------------------------------------------------------------------
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# -----------------------------------------------------------------------
# Prepare Ground Truth for Verifier
# -----------------------------------------------------------------------
TRUTH_CONTENT=""
if [ -f "$GROUND_TRUTH_PATH" ]; then
    TRUTH_CONTENT=$(cat "$GROUND_TRUTH_PATH" | base64 -w 0)
fi

# -----------------------------------------------------------------------
# Create Result JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "ground_truth_b64": "$TRUTH_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="