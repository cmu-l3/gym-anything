#!/bin/bash
echo "=== Exporting Chi-Square Titanic Results ==="

# Source utilities not available, writing explicit logic

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_PATH="/home/ga/Documents/JASP/chi_square_results.txt"
PROJECT_PATH="/home/ga/Documents/JASP/TitanicChiSquare.jasp"

# 1. Check Results Text File
RESULTS_EXISTS="false"
RESULTS_CREATED_DURING_TASK="false"
RESULTS_CONTENT=""

if [ -f "$RESULTS_PATH" ]; then
    RESULTS_EXISTS="true"
    MTIME=$(stat -c %Y "$RESULTS_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        RESULTS_CREATED_DURING_TASK="true"
    fi
    # Read content (limit size for safety)
    RESULTS_CONTENT=$(head -c 1024 "$RESULTS_PATH" | base64 -w 0)
fi

# 2. Check JASP Project File
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING_TASK="false"
PROJECT_SIZE="0"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    PROJECT_SIZE="$SIZE"
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check App State
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "results_exists": $RESULTS_EXISTS,
    "results_created_during_task": $RESULTS_CREATED_DURING_TASK,
    "results_content_base64": "$RESULTS_CONTENT",
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_size_bytes": $PROJECT_SIZE,
    "project_path": "$PROJECT_PATH",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="