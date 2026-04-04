#!/bin/bash
echo "=== Exporting Tidal Turbine Simulation Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/projects/tidal_project.wpa"
REPORT_PATH="/home/ga/Documents/tidal_report.txt"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Report File and Extract Value
REPORT_EXISTS="false"
REPORT_CONTENT=""
EXTRACTED_VALUE=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(head -n 5 "$REPORT_PATH") # Read first few lines
    
    # Attempt to extract a number using regex (looks for float patterns)
    # This grabs the first valid number found in the file
    EXTRACTED_VALUE=$(grep -oE '[0-9]+(\.[0-9]+)?' "$REPORT_PATH" | head -1)
fi

# 3. Check if QBlade is still running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')",
    "extracted_power_value": "${EXTRACTED_VALUE:-0}",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
write_result_json "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "=== Export complete ==="