#!/bin/bash
echo "=== Exporting identify_countries_without_major_rivers result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_BASE="/home/ga/gvsig_data/exports/arid_countries"
SHP_FILE="${OUTPUT_BASE}.shp"
DBF_FILE="${OUTPUT_BASE}.dbf"
SHX_FILE="${OUTPUT_BASE}.shx"

# Check output existence and modification time
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$SHP_FILE" ] && [ -f "$DBF_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$SHP_FILE" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$SHP_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if application was running
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
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
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "shp_path": "$SHP_FILE",
    "dbf_path": "$DBF_FILE",
    "shx_path": "$SHX_FILE"
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="