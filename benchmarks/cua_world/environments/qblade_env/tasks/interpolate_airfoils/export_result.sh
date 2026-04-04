#!/bin/bash
echo "=== Exporting interpolate_airfoils result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target file
OUTPUT_PATH="/home/ga/Documents/airfoils/interpolated_naca_50pct.dat"

# Check file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if QBlade was running
APP_RUNNING=$(is_qblade_running)
APP_WAS_RUNNING="false"
if [ "$APP_RUNNING" -gt "0" ]; then
    APP_WAS_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_WAS_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save JSON result
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

# Prepare output file for export (copy to temp for verifier access if needed, 
# though verifier will usually copy directly from path)
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/interpolated_output.dat
    chmod 666 /tmp/interpolated_output.dat
fi

echo "=== Export complete ==="