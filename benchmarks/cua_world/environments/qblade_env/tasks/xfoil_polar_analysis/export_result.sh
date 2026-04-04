#!/bin/bash
echo "=== Exporting xfoil_polar_analysis result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
POLAR_FILE="/home/ga/Documents/polar_analysis_output.txt"
SUMMARY_FILE="/home/ga/Documents/polar_summary.txt"

# Check Polar File
POLAR_EXISTS="false"
POLAR_CREATED_DURING="false"
POLAR_SIZE=0
if [ -f "$POLAR_FILE" ]; then
    POLAR_EXISTS="true"
    POLAR_SIZE=$(stat -c%s "$POLAR_FILE")
    POLAR_MTIME=$(stat -c%Y "$POLAR_FILE")
    if [ "$POLAR_MTIME" -gt "$TASK_START" ]; then
        POLAR_CREATED_DURING="true"
    fi
fi

# Check Summary File
SUMMARY_EXISTS="false"
SUMMARY_CREATED_DURING="false"
if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_MTIME=$(stat -c%Y "$SUMMARY_FILE")
    if [ "$SUMMARY_MTIME" -gt "$TASK_START" ]; then
        SUMMARY_CREATED_DURING="true"
    fi
fi

# Check if QBlade is still running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
# We do NOT include the file content here to avoid JSON escaping issues.
# The verifier will copy the actual text files using copy_from_env.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "polar_file_exists": $POLAR_EXISTS,
    "polar_created_during_task": $POLAR_CREATED_DURING,
    "polar_size_bytes": $POLAR_SIZE,
    "summary_file_exists": $SUMMARY_EXISTS,
    "summary_created_during_task": $SUMMARY_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "polar_path": "$POLAR_FILE",
    "summary_path": "$SUMMARY_FILE"
}
EOF

# Save result safely
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="