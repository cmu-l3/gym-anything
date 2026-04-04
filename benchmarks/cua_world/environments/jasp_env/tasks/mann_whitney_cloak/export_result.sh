#!/bin/bash
echo "=== Exporting Mann-Whitney U Test Results ==="

# Record timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
REPORT_PATH="/home/ga/Documents/JASP/mann_whitney_report.txt"
PROJECT_PATH="/home/ga/Documents/JASP/MannWhitneyCloak.jasp"

# 1. Check Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read content safely (max 2KB)
    REPORT_CONTENT=$(head -c 2048 "$REPORT_PATH" | base64 -w 0)
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    else
        REPORT_CREATED_DURING_TASK="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
    REPORT_CONTENT=""
    REPORT_CREATED_DURING_TASK="false"
fi

# 2. Check JASP Project File
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH" 2>/dev/null || echo "0")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    else
        PROJECT_CREATED_DURING_TASK="false"
    fi
else
    PROJECT_EXISTS="false"
    PROJECT_SIZE="0"
    PROJECT_CREATED_DURING_TASK="false"
fi

# 3. Check if JASP is running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
# Use mktemp to avoid permission issues, then move
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "report_file": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "size_bytes": $REPORT_SIZE,
        "content_base64": "$REPORT_CONTENT"
    },
    "project_file": {
        "exists": $PROJECT_EXISTS,
        "created_during_task": $PROJECT_CREATED_DURING_TASK,
        "size_bytes": $PROJECT_SIZE
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location and ensure readable
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="