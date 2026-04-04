#!/bin/bash
echo "=== Exporting river_border_crossings result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_BASE="/home/ga/gvsig_data/exports/river_crossings"
OUTPUT_SHP="${OUTPUT_BASE}.shp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output existence and timestamp
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Zip the shapefile components for the verifier to download
# The verifier needs .shp, .shx, and .dbf to analyze geometry fully
ZIP_PATH="/tmp/output_shapefile.zip"
rm -f "$ZIP_PATH"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    # Zip all related files (shp, shx, dbf, prj, cpg)
    zip -j "$ZIP_PATH" "${OUTPUT_BASE}".* 2>/dev/null || true
    echo "Zipped output shapefile to $ZIP_PATH"
fi

# Check if gvSIG is still running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

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
    "zip_available": $([ -f "$ZIP_PATH" ] && echo "true" || echo "false")
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json