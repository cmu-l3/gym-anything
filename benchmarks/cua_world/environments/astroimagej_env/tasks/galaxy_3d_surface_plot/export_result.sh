#!/bin/bash
echo "=== Exporting galaxy_3d_surface_plot result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target output file
OUTPUT_PATH="/home/ga/AstroImages/processed/galaxy_core_surface.png"

# Take final screenshot as part of the evidence trajectory
take_screenshot /tmp/task_final.png

# Check if output file exists and when it was created
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if the file was created AFTER the task started
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
    
    # Check if the saved file is a valid image using Python
    VALID_IMG=$(python3 -c "from PIL import Image; img=Image.open('$OUTPUT_PATH'); img.verify(); print('true')" 2>/dev/null || echo "false")
else
    OUTPUT_EXISTS="false"
    OUTPUT_MTIME="0"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
    VALID_IMG="false"
fi

# Check if AstroImageJ is still running
APP_RUNNING=$(is_aij_running && echo "true" || echo "false")

# Save all results to a JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "valid_image": $VALID_IMG,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location ensuring proper read permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="