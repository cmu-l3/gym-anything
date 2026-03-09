#!/bin/bash
echo "=== Exporting calculate_true_areas result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_BASE="/home/ga/gvsig_data/exports/countries_area"
OUTPUT_SHP="${OUTPUT_BASE}.shp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists
if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi

    # Zip the shapefile components for the verifier to download
    # A shapefile consists of at least .shp, .shx, .dbf
    # We also want .prj to check projection
    echo "Zipping shapefile components for verification..."
    cd /home/ga/gvsig_data/exports
    zip -j /tmp/countries_area_result.zip countries_area.shp countries_area.shx countries_area.dbf countries_area.prj 2>/dev/null || true
    chmod 666 /tmp/countries_area_result.zip
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Check if gvSIG is running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Create basic JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "zip_path": "/tmp/countries_area_result.zip",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="