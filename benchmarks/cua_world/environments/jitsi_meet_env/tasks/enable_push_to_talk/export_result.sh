#!/bin/bash
echo "=== Exporting enable_push_to_talk results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected files
FILE_SETTINGS="/home/ga/ptt_settings.png"
FILE_INACTIVE="/home/ga/ptt_inactive.png"
FILE_ACTIVE="/home/ga/ptt_active.png"

# Helper to get file stats
get_file_stats() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during, \"path\": \"$fpath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false, \"path\": \"$fpath\"}"
    fi
}

STATS_SETTINGS=$(get_file_stats "$FILE_SETTINGS")
STATS_INACTIVE=$(get_file_stats "$FILE_INACTIVE")
STATS_ACTIVE=$(get_file_stats "$FILE_ACTIVE")

# Take final screenshot of the desktop
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "settings": $STATS_SETTINGS,
        "inactive": $STATS_INACTIVE,
        "active": $STATS_ACTIVE
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"