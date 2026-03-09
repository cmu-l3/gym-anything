#!/bin/bash
echo "=== Exporting Chi-Square Independence results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROJECT_PATH="/home/ga/Documents/Jamovi/TitanicChiSquare.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/chisquare_report.txt"

# 1. Check Project File (.omv)
OMV_EXISTS="false"
OMV_CREATED_DURING_TASK="false"
OMV_SIZE="0"

if [ -f "$PROJECT_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$PROJECT_PATH")
    OMV_MTIME=$(stat -c %Y "$PROJECT_PATH")
    
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Report File (.txt)
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (base64 encode to avoid JSON breaking chars)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
fi

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING_TASK,
    "omv_size_bytes": $OMV_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "project_path": "$PROJECT_PATH"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="