#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/Documents/gretl_output"

# Helper function to get file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Check expected files
INFO_SCRIPT=$(get_file_info "$OUTPUT_DIR/pca_analysis.inp")
INFO_RESULTS=$(get_file_info "$OUTPUT_DIR/pca_results.txt")
INFO_DATASET=$(get_file_info "$OUTPUT_DIR/wage_survey_pca.gdt")

# Check if Gretl is running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "files": {
        "script": $INFO_SCRIPT,
        "results": $INFO_RESULTS,
        "dataset": $INFO_DATASET
    }
}
EOF

# Move result to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="