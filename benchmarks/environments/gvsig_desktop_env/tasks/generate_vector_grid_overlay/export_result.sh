#!/bin/bash
echo "=== Exporting generate_vector_grid_overlay results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_BASE="/home/ga/gvsig_data/exports/australia_grid"
SHP_FILE="${OUTPUT_BASE}.shp"

# Check if output file exists
if [ -f "$SHP_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$SHP_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$SHP_FILE" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi

    # Zip the shapefile components for the verifier to download
    # Shapefiles consist of .shp, .shx, .dbf, and optionally .prj
    echo "Zipping shapefile components..."
    zip -j /tmp/australia_grid.zip "${OUTPUT_BASE}".* 2>/dev/null || echo "Zip failed"
    chmod 666 /tmp/australia_grid.zip 2>/dev/null || true
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_running": $APP_RUNNING,
    "zip_available": $([ -f "/tmp/australia_grid.zip" ] && echo "true" || echo "false")
}
EOF

# Move result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json