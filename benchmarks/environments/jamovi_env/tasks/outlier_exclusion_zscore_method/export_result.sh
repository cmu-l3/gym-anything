#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Record End Time and Load Start Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Define Expected Paths
REPORT_PATH="/home/ga/Documents/Jamovi/outlier_report.txt"
OMV_PATH="/home/ga/Documents/Jamovi/Age_Outlier_Removal.omv"
DATASET_PATH="/home/ga/Documents/Jamovi/BFI25.csv"

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Copy for verifier
    cp "$REPORT_PATH" /tmp/outlier_report.txt
    chmod 666 /tmp/outlier_report.txt
fi

# 4. Check OMV File
OMV_EXISTS="false"
OMV_CREATED_DURING_TASK="false"
if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_MTIME=$(stat -c %Y "$OMV_PATH")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING_TASK="true"
    fi
    # Copy for verifier
    cp "$OMV_PATH" /tmp/result.omv
    chmod 666 /tmp/result.omv
fi

# 5. Copy Dataset for Verifier (Ground Truth Calculation)
if [ -f "$DATASET_PATH" ]; then
    cp "$DATASET_PATH" /tmp/source_data.csv
    chmod 666 /tmp/source_data.csv
fi

# 6. Check if Jamovi is still running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# 7. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 8. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"