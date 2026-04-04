#!/bin/bash
echo "=== Exporting Mediation Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/tmp/task_result.json"

PROJECT_PATH="/home/ga/Documents/Jamovi/Mediation_ExamAnxiety.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/mediation_report.txt"

# 1. Check Project File (.omv)
OMV_EXISTS="false"
OMV_VALID="false"
if [ -f "$PROJECT_PATH" ]; then
    OMV_EXISTS="true"
    OMV_MTIME=$(stat -c %Y "$PROJECT_PATH")
    OMV_SIZE=$(stat -c %s "$PROJECT_PATH")
    
    if [ "$OMV_MTIME" -gt "$TASK_START" ] && [ "$OMV_SIZE" -gt 5000 ]; then
        OMV_VALID="true"
    fi
fi

# 2. Check Report File (.txt)
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content, escape quotes/newlines for JSON
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
fi

# 3. Get Ground Truth
GROUND_TRUTH="{}"
if [ -f "/tmp/ground_truth.json" ]; then
    GROUND_TRUTH=$(cat /tmp/ground_truth.json)
fi

# 4. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Build Result JSON
cat > "$RESULT_FILE" << EOF
{
    "omv_exists": $OMV_EXISTS,
    "omv_valid_timestamp": $OMV_VALID,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "ground_truth": $GROUND_TRUTH,
    "task_start_time": $TASK_START
}
EOF

# Permission fix
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result stored in $RESULT_FILE"