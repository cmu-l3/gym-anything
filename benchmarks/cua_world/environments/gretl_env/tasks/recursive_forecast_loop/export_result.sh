#!/bin/bash
set -euo pipefail

echo "=== Exporting recursive_forecast_loop results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_PATH="$OUTPUT_DIR/recursive_forecast.inp"
RESULT_PATH="$OUTPUT_DIR/rmsfe_results.txt"
CSV_PATH="$OUTPUT_DIR/forecast_errors.csv"

# Function to gather file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        # Check if created/modified during task
        local valid_time="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            valid_time="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"valid_time\": $valid_time}"
    else
        echo "{\"exists\": false, \"size\": 0, \"valid_time\": false}"
    fi
}

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if Gretl is still running
GRETL_RUNNING="false"
if is_gretl_running; then
    GRETL_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gretl_running": $GRETL_RUNNING,
    "script_info": $(get_file_info "$SCRIPT_PATH"),
    "result_info": $(get_file_info "$RESULT_PATH"),
    "csv_info": $(get_file_info "$CSV_PATH"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to accessible location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result export complete:"
cat /tmp/task_result.json