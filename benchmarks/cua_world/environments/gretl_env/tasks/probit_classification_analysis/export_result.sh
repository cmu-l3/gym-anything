#!/bin/bash
echo "=== Exporting Probit Classification Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/gretl_output/classification_report.txt"
SCORE_PATH="/home/ga/Documents/gretl_output/accuracy_score.txt"

# Helper function to check file stats
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true|$size"
        else
            echo "false|$size"
        fi
    else
        echo "missing|0"
    fi
}

# Check Report File
IFS='|' read -r REPORT_CREATED REPORT_SIZE <<< "$(check_file "$REPORT_PATH")"

# Check Score File
IFS='|' read -r SCORE_CREATED SCORE_SIZE <<< "$(check_file "$SCORE_PATH")"

# App running status
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "report_file": {
        "exists": $([ "$REPORT_CREATED" != "missing" ] && echo "true" || echo "false"),
        "created_during_task": $REPORT_CREATED,
        "size_bytes": $REPORT_SIZE,
        "path": "$REPORT_PATH"
    },
    "score_file": {
        "exists": $([ "$SCORE_CREATED" != "missing" ] && echo "true" || echo "false"),
        "created_during_task": $SCORE_CREATED,
        "size_bytes": $SCORE_SIZE,
        "path": "$SCORE_PATH"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json