#!/bin/bash
echo "=== Exporting Cohort Survival Analysis Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/Jamovi/cohort_report.txt"
OMV_PATH="/home/ga/Documents/Jamovi/Titanic_Cohorts.omv"

# Check output report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    else
        REPORT_CREATED_DURING="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_CREATED_DURING="false"
fi

# Check OMV file
if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH" 2>/dev/null || echo "0")
    # Verify it's a ZIP file (OMV format is zip-based)
    if file "$OMV_PATH" | grep -q "Zip archive"; then
        OMV_VALID="true"
    else
        OMV_VALID="false"
    fi
else
    OMV_EXISTS="false"
    OMV_SIZE="0"
    OMV_VALID="false"
fi

# Check if Jamovi is running
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "omv_exists": $OMV_EXISTS,
    "omv_valid": $OMV_VALID,
    "omv_size_bytes": $OMV_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "=== Export complete ==="