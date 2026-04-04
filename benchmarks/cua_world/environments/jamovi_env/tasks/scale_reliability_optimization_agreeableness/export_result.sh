#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
OMV_PATH="/home/ga/Documents/Jamovi/Agreeableness_Reliability.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/reliability_report.txt"
DATASET_PATH="/home/ga/Documents/Jamovi/BFI25.csv"

# Check OMV file
if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH" 2>/dev/null || echo "0")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING_TASK="true"
    else
        OMV_CREATED_DURING_TASK="false"
    fi
else
    OMV_EXISTS="false"
    OMV_SIZE="0"
    OMV_CREATED_DURING_TASK="false"
fi

# Check Report file
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    else
        REPORT_CREATED_DURING_TASK="false"
    fi
    
    # Read report content (first 3 lines)
    REPORT_CONTENT=$(head -n 3 "$REPORT_PATH" | tr '\n' '|')
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
    REPORT_CREATED_DURING_TASK="false"
    REPORT_CONTENT=""
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare files for extraction (copy to /tmp so verifier can access them via copy_from_env)
# The verifier needs the OMV (to check settings), the report (to check answers), and the data (to calc ground truth)
cp "$OMV_PATH" /tmp/result_project.omv 2>/dev/null || true
cp "$REPORT_PATH" /tmp/result_report.txt 2>/dev/null || true
cp "$DATASET_PATH" /tmp/ground_truth_data.csv 2>/dev/null || true

# Make readable
chmod 644 /tmp/result_project.omv /tmp/result_report.txt /tmp/ground_truth_data.csv 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING_TASK,
    "omv_size": $OMV_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_preview": "$REPORT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="