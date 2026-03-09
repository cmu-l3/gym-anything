#!/bin/bash
echo "=== Exporting generate_remote_areas_difference result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_SHP="/home/ga/gvsig_data/exports/remote_areas.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/remote_areas.dbf"
OUTPUT_SHX="/home/ga/gvsig_data/exports/remote_areas.shx"

# Check output existence and stats
EXISTS="false"
FILE_SIZE=0
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_SHP" ]; then
    EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Check if gvSIG is still running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $EXISTS,
    "file_created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy of JSON
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Prepare files for verification (copy to /tmp so verifier can grab them)
# The verifier needs the .shp, .shx, and .dbf to read the shapefile
if [ "$EXISTS" = "true" ]; then
    cp "$OUTPUT_SHP" /tmp/remote_areas.shp 2>/dev/null || true
    cp "$OUTPUT_DBF" /tmp/remote_areas.dbf 2>/dev/null || true
    cp "$OUTPUT_SHX" /tmp/remote_areas.shx 2>/dev/null || true
    chmod 644 /tmp/remote_areas.* 2>/dev/null || true
fi

echo "Export complete. Result:"
cat /tmp/task_result.json