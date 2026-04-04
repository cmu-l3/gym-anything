#!/bin/bash
echo "=== Exporting data_frequency_conversion result ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_PATH="/home/ga/Documents/gretl_output/usa_annual.csv"
TASK_START_FILE="/tmp/task_specific_start_time.txt"
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# capture final screenshot
take_screenshot /tmp/task_final.png

# Check if Gretl was running (anti-gaming)
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# Check output file details
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Copy the actual output CSV to a temp location for the verifier to read
# (The verifier uses copy_from_env to pull this out)
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/agent_output.csv
    chmod 666 /tmp/agent_output.csv
fi

echo "Result exported to /tmp/task_result.json"