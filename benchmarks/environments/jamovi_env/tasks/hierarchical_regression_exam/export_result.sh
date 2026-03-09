#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Files to check
OMV_FILE="/home/ga/Documents/Jamovi/HierarchicalRegression.omv"
REPORT_FILE="/home/ga/Documents/Jamovi/hierarchical_regression_report.txt"

# Check .omv file
OMV_EXISTS="false"
OMV_SIZE=0
OMV_CREATED_DURING="false"
if [ -f "$OMV_FILE" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c%s "$OMV_FILE")
    OMV_MTIME=$(stat -c%Y "$OMV_FILE")
    if [ "$OMV_MTIME" -ge "$TASK_START" ]; then
        OMV_CREATED_DURING="true"
    fi
fi

# Check report file
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(base64 -w 0 "$REPORT_FILE") # Encode to avoid JSON breaking
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# App status
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_size": $OMV_SIZE,
    "omv_fresh": $OMV_CREATED_DURING,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "report_fresh": $REPORT_CREATED_DURING,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export Complete ==="