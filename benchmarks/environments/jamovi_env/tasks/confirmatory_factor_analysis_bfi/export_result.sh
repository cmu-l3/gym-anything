#!/bin/bash
echo "=== Exporting CFA task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_FILE="/home/ga/Documents/Jamovi/CFA_results.txt"
PROJECT_FILE="/home/ga/Documents/Jamovi/BFI25_CFA.omv"

# Check Results File
RESULTS_EXISTS="false"
RESULTS_CREATED_DURING="false"
RESULTS_CONTENT=""

if [ -f "$RESULTS_FILE" ]; then
    RESULTS_EXISTS="true"
    R_TIME=$(stat -c%Y "$RESULTS_FILE" 2>/dev/null || echo 0)
    if [ "$R_TIME" -ge "$TASK_START" ]; then
        RESULTS_CREATED_DURING="true"
    fi
    # Capture content for JSON (limited to first 20 lines)
    RESULTS_CONTENT=$(head -n 20 "$RESULTS_FILE" | base64 -w 0)
fi

# Check Project File
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING="false"
PROJECT_SIZE=0

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    P_TIME=$(stat -c%Y "$PROJECT_FILE" 2>/dev/null || echo 0)
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE" 2>/dev/null || echo 0)
    if [ "$P_TIME" -ge "$TASK_START" ]; then
        PROJECT_CREATED_DURING="true"
    fi
fi

# Check if Jamovi is running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "results_exists": $RESULTS_EXISTS,
    "results_created_during_task": $RESULTS_CREATED_DURING,
    "results_content_b64": "$RESULTS_CONTENT",
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING,
    "project_size_bytes": $PROJECT_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"