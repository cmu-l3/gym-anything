#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/JASP/power_report.txt"
JASP_PATH="/home/ga/Documents/JASP/PowerAnalysis.jasp"

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content for verification (limit size just in case)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH" | base64 -w 0)
fi

# 2. Check JASP Project File
JASP_EXISTS="false"
JASP_CREATED_DURING_TASK="false"
if [ -f "$JASP_PATH" ]; then
    JASP_EXISTS="true"
    JASP_MTIME=$(stat -c %Y "$JASP_PATH" 2>/dev/null || echo "0")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT",
    "jasp_exists": $JASP_EXISTS,
    "jasp_created_during_task": $JASP_CREATED_DURING_TASK,
    "jasp_path": "$JASP_PATH"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="