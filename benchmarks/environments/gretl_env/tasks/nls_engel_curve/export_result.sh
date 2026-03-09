#!/bin/bash
echo "=== Exporting nls_engel_curve results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCRIPT_PATH="/home/ga/Documents/gretl_output/nls_engel.inp"
OUTPUT_PATH="/home/ga/Documents/gretl_output/nls_engel_output.txt"

# Helper function to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local created_in_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_in_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_in_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

SCRIPT_STATUS=$(check_file "$SCRIPT_PATH")
OUTPUT_STATUS=$(check_file "$OUTPUT_PATH")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_file": $SCRIPT_STATUS,
    "output_file": $OUTPUT_STATUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="