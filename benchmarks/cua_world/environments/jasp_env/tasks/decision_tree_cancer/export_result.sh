#!/bin/bash
echo "=== Exporting Decision Tree Results ==="

# Define paths
PROJECT_PATH="/home/ga/Documents/JASP/cancer_tree.jasp"
REPORT_PATH="/home/ga/Documents/JASP/tree_report.txt"
TASK_START_FILE="/tmp/task_start_time.txt"

# Get start time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_VALID_TIME="false"
PROJECT_SIZE=0

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_PATH")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_VALID_TIME="true"
    fi
    
    # Copy for verification
    cp "$PROJECT_PATH" /tmp/cancer_tree.jasp
    chmod 666 /tmp/cancer_tree.jasp
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_VALID_TIME="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH")
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Limit size
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_VALID_TIME="true"
    fi
fi

# 3. Check if JASP is running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "project_exists": $PROJECT_EXISTS,
    "project_valid_time": $PROJECT_VALID_TIME,
    "project_size_bytes": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_valid_time": $REPORT_VALID_TIME,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json