#!/bin/bash
echo "=== Exporting floorplan_gis_overlay results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/LibreCAD/floorplan_gis.dxf"
ORIGINAL_FILE="/home/ga/Documents/LibreCAD/floorplan.dxf"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check application state
APP_RUNNING="false"
if pgrep -f librecad > /dev/null; then
    APP_RUNNING="true"
fi

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if original file was preserved (anti-gaming)
ORIGINAL_PRESERVED="false"
if [ -f "$ORIGINAL_FILE" ]; then
    CURRENT_ORIG_HASH=$(md5sum "$ORIGINAL_FILE" | awk '{print $1}')
    INITIAL_ORIG_HASH=$(cat /tmp/initial_file_hash.txt | awk '{print $1}' 2>/dev/null || echo "")
    
    if [ "$CURRENT_ORIG_HASH" == "$INITIAL_ORIG_HASH" ]; then
        ORIGINAL_PRESERVED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_FILE",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "original_preserved": $ORIGINAL_PRESERVED,
    "output_size": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="