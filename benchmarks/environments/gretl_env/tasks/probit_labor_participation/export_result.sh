#!/bin/bash
echo "=== Exporting Probit Labor Participation Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_FILE="/home/ga/Documents/gretl_output/probit_results.txt"
PROBS_FILE="/home/ga/Documents/gretl_output/predicted_probabilities.csv"

# Function to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "true|$size|$mtime"
        else
            echo "false|$size|$mtime"  # Exists but old
        fi
    else
        echo "false|0|0"
    fi
}

# Check files
IFS='|' read -r RES_CREATED RES_SIZE RES_MTIME <<< "$(check_file "$RESULTS_FILE")"
IFS='|' read -r PROB_CREATED PROB_SIZE PROB_MTIME <<< "$(check_file "$PROBS_FILE")"

# Check if Gretl was running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "results_file": {
        "exists": $([ -f "$RESULTS_FILE" ] && echo "true" || echo "false"),
        "created_during_task": $RES_CREATED,
        "size_bytes": $RES_SIZE,
        "path": "$RESULTS_FILE"
    },
    "probs_file": {
        "exists": $([ -f "$PROBS_FILE" ] && echo "true" || echo "false"),
        "created_during_task": $PROB_CREATED,
        "size_bytes": $PROB_SIZE,
        "path": "$PROBS_FILE"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="