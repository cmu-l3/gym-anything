#!/bin/bash
set -e
echo "=== Exporting export_layer_to_kml results ==="

source /workspace/scripts/task_utils.sh

# Define paths
OUTPUT_PATH="/home/ga/gvsig_data/exports/world_countries.kml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file status
OUTPUT_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if gvSIG is still running (it should be)
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create result JSON
# We create it in a temp location and move it to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "file_size_bytes": $FILE_SIZE_BYTES,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# 5. Prepare the KML file for verification (make it accessible)
if [ "$OUTPUT_EXISTS" == "true" ]; then
    cp "$OUTPUT_PATH" /tmp/exported_file.kml
    chmod 666 /tmp/exported_file.kml
fi

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="