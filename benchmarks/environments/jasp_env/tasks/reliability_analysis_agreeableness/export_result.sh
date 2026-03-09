#!/bin/bash
echo "=== Exporting Reliability Analysis Results ==="

# Define paths
PROJECT_FILE="/home/ga/Documents/JASP/Agreeableness_Reliability.jasp"
REPORT_FILE="/home/ga/Documents/JASP/reliability_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING="false"
PROJECT_SIZE="0"
if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE")
    FILE_MTIME=$(stat -c%Y "$PROJECT_FILE")
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        PROJECT_CREATED_DURING="true"
    fi
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        REPORT_CREATED_DURING="true"
    fi
    # Read content safely (encode to base64 to avoid JSON breaking chars, or just cat if safe)
    # We'll rely on verify script copying the file, but putting content here helps quick debug
    REPORT_CONTENT="[File exists]" 
fi

# 3. Check JASP Status
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $START_TIME,
    "task_end": $CURRENT_TIME,
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING,
    "project_size": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="