#!/bin/bash
echo "=== Exporting determine_runaway_rpm results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
REPORT_PATH="/home/ga/Documents/projects/runaway_report.txt"
DATA_PATH="/home/ga/Documents/projects/runaway_data.txt"
PROJECT_PATH="/home/ga/Documents/projects/safety_analysis.wpa"

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -n 5) # Read first few lines
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Data File
DATA_EXISTS="false"
DATA_SIZE=0
DATA_CREATED_DURING_TASK="false"
if [ -f "$DATA_PATH" ]; then
    DATA_EXISTS="true"
    DATA_SIZE=$(stat -c %s "$DATA_PATH" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$DATA_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        DATA_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
fi

# 4. Check if QBlade is running
APP_RUNNING=$(is_qblade_running)
if [ "$APP_RUNNING" != "0" ]; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON result
# Note: We don't read the full data file here, the verifier will copy it.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g')",
    "data_exists": $DATA_EXISTS,
    "data_created_during_task": $DATA_CREATED_DURING_TASK,
    "data_size_bytes": $DATA_SIZE,
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="