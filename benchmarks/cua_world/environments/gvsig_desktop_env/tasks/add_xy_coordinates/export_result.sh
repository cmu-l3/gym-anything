#!/bin/bash
echo "=== Exporting add_xy_coordinates results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for output files
OUTPUT_BASE="/home/ga/gvsig_data/exports/cities_with_coords"
SHP="$OUTPUT_BASE.shp"
DBF="$OUTPUT_BASE.dbf"
SHX="$OUTPUT_BASE.shx"

FILES_EXIST="false"
if [ -f "$SHP" ] && [ -f "$DBF" ]; then
    FILES_EXIST="true"
fi

# 3. Check timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ "$FILES_EXIST" = "true" ]; then
    FILE_TIME=$(stat -c %Y "$SHP" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Package shapefile for verification
# We zip the shapefile components so the verifier can copy one file
ZIP_PATH="/tmp/cities_with_coords.zip"
rm -f "$ZIP_PATH"

if [ "$FILES_EXIST" = "true" ]; then
    echo "Zipping shapefile for verification..."
    # Zip all components (.shp, .shx, .dbf, .prj)
    zip -j "$ZIP_PATH" "$OUTPUT_BASE".* 2>/dev/null
fi

# 5. Check if gvSIG was running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# 6. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "files_exist": $FILES_EXIST,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "zip_path": "$ZIP_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"