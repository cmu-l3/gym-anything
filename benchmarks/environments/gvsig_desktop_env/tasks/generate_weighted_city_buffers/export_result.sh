#!/bin/bash
echo "=== Exporting generate_weighted_city_buffers result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
OUTPUT_DIR="/home/ga/gvsig_data/exports"
OUTPUT_SHP="$OUTPUT_DIR/city_influence.shp"
OUTPUT_SHX="$OUTPUT_DIR/city_influence.shx"
OUTPUT_DBF="$OUTPUT_DIR/city_influence.dbf"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output files
if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Check if gvSIG is running
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "file_created_during_task": $CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Copy output files for verification (handling permissions)
# We copy them to /tmp so the verifier can read them easily via copy_from_env
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_SHP" /tmp/verify_output.shp
    cp "$OUTPUT_SHX" /tmp/verify_output.shx 2>/dev/null || true
    cp "$OUTPUT_DBF" /tmp/verify_output.dbf 2>/dev/null || true
    chmod 644 /tmp/verify_output.*
fi

# Save result JSON
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json