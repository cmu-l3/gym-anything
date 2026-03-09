#!/bin/bash
echo "=== Exporting analyze_fixed_rpm_stall results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Define file paths
DATA_FILE="/home/ga/Documents/projects/stall_simulation_data.txt"
REPORT_FILE="/home/ga/Documents/projects/stall_report.txt"
PROJECT_FILE="/home/ga/Documents/projects/stall_analysis.wpa"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check Data File
DATA_EXISTS="false"
DATA_SIZE=0
DATA_NEW="false"
if [ -f "$DATA_FILE" ]; then
    DATA_EXISTS="true"
    DATA_SIZE=$(stat -c%s "$DATA_FILE")
    MTIME=$(stat -c%Y "$DATA_FILE")
    if [ "$MTIME" -gt "$START_TIME" ]; then
        DATA_NEW="true"
    fi
fi

# 4. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_NEW="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read first 200 chars safely for JSON embedding
    REPORT_CONTENT=$(head -c 200 "$REPORT_FILE" | tr -d '\000-\031' | sed 's/"/\\"/g')
    MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$MTIME" -gt "$START_TIME" ]; then
        REPORT_NEW="true"
    fi
fi

# 5. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_NEW="false"
if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE")
    MTIME=$(stat -c%Y "$PROJECT_FILE")
    if [ "$MTIME" -gt "$START_TIME" ]; then
        PROJECT_NEW="true"
    fi
fi

# 6. Check if QBlade is running
APP_RUNNING=$(is_qblade_running)

# 7. Create JSON result
# Note: We don't verify the content logic here (Python verifier does that).
# We just export existence/metadata.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $START_TIME,
    "timestamp": "$(date -Iseconds)",
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "data_file": {
        "exists": $DATA_EXISTS,
        "path": "$DATA_FILE",
        "size": $DATA_SIZE,
        "created_during_task": $DATA_NEW
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "path": "$REPORT_FILE",
        "content_snippet": "$REPORT_CONTENT",
        "created_during_task": $REPORT_NEW
    },
    "project_file": {
        "exists": $PROJECT_EXISTS,
        "path": "$PROJECT_FILE",
        "size": $PROJECT_SIZE,
        "created_during_task": $PROJECT_NEW
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="