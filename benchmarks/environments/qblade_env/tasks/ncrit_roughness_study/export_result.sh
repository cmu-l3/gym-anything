#!/bin/bash
echo "=== Exporting Ncrit roughness study results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_FILE="/home/ga/Documents/roughness_study_results.txt"
PROJECT_FILE="/home/ga/Documents/projects/roughness_study.wpa"

# 1. Check Text Report
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$RESULTS_FILE" ]; then
    REPORT_EXISTS="true"
    R_MTIME=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
    if [ "$R_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content (base64 encode to safely put in JSON)
    REPORT_CONTENT=$(cat "$RESULTS_FILE" | base64 -w 0)
fi

# 2. Check Project File
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING_TASK="false"
PROJECT_SIZE=0

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    P_MTIME=$(stat -c %Y "$PROJECT_FILE" 2>/dev/null || echo "0")
    PROJECT_SIZE=$(stat -c %s "$PROJECT_FILE" 2>/dev/null || echo "0")
    
    if [ "$P_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Application State
APP_RUNNING=$(pgrep -f "[Qq][Bb]lade" > /dev/null && echo "true" || echo "false")

# 4. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_size_bytes": $PROJECT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="