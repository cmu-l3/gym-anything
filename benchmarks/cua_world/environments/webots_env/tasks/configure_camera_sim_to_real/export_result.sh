#!/bin/bash
echo "=== Exporting configure_camera_sim_to_real result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as visual evidence
take_screenshot /tmp/task_final.png

# Retrieve task start time to verify file wasn't created before task started
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Desktop/sim_to_real_camera.wbt"

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

# Examine the required output file
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check anti-gaming timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Determine if the application remained open
APP_RUNNING="false"
if pgrep -f "webots" > /dev/null; then
    APP_RUNNING="true"
fi

# Write findings to a JSON dictionary
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "output_path": "$OUTPUT_PATH"
}
EOF

# Safely copy to standard evaluation location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="