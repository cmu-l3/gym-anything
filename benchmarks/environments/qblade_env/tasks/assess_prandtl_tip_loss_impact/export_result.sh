#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Task End Time & Final Screenshot
TASK_END_TIME=$(date +%s)
take_screenshot /tmp/task_final.png

# 2. Define Paths
RESULTS_DIR="/home/ga/Documents/results"
FILE_WITH_LOSS="$RESULTS_DIR/with_loss.txt"
FILE_NO_LOSS="$RESULTS_DIR/no_loss.txt"
FILE_REPORT="$RESULTS_DIR/loss_report.txt"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Helper to read file content safely
read_file_content() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        # Read first 50 lines to avoid massive JSONs if they export binary garbage
        head -n 50 "$fpath" | base64 -w 0
    else
        echo ""
    fi
}

# 4. Check File Stats
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START_TIME" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# 5. Gather QBlade State
APP_RUNNING=$(is_qblade_running)

# 6. Construct JSON Result
# We embed the Base64 content of the files so the python verifier can parse the physics data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START_TIME,
    "task_end": $TASK_END_TIME,
    "app_was_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "files": {
        "with_loss": $(check_file "$FILE_WITH_LOSS"),
        "no_loss": $(check_file "$FILE_NO_LOSS"),
        "report": $(check_file "$FILE_REPORT")
    },
    "content_b64": {
        "with_loss": "$(read_file_content "$FILE_WITH_LOSS")",
        "no_loss": "$(read_file_content "$FILE_NO_LOSS")",
        "report": "$(read_file_content "$FILE_REPORT")"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Save to shared location
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="