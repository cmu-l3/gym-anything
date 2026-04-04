#!/bin/bash
echo "=== Exporting ARMA Inflation Forecast Result ==="

source /workspace/scripts/task_utils.sh

# Paths
SCRIPT_PATH="/home/ga/Documents/gretl_output/inflation_forecast.inp"
OUTPUT_PATH="/home/ga/Documents/gretl_output/inflation_forecast_output.txt"
REF_JSON="/tmp/reference_values.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Record file stats
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local sz=$(stat -c%s "$f")
        local mt=$(stat -c%Y "$f")
        local created_during=$([ "$mt" -gt "$TASK_START" ] && echo "true" || echo "false")
        echo "\"exists\": true, \"size\": $sz, \"mtime\": $mt, \"created_during_task\": $created_during"
    else
        echo "\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false"
    fi
}

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
OUTPUT_STATS=$(check_file "$OUTPUT_PATH")
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": { $SCRIPT_STATS },
    "output_file": { $OUTPUT_STATS },
    "screenshot_path": "/tmp/task_final.png",
    "reference_values_path": "$REF_JSON",
    "agent_script_path": "$SCRIPT_PATH",
    "agent_output_path": "$OUTPUT_PATH"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON created at /tmp/task_result.json"
echo "=== Export Complete ==="