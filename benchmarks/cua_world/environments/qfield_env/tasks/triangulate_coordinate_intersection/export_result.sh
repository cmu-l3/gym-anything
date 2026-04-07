#!/system/bin/sh
echo "=== Exporting Task Results ==="

# Define paths
TASK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
EXPORT_PATH="/sdcard/task_result.gpkg"
START_TIME_FILE="/sdcard/task_start_time.txt"

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Check if the GeoPackage exists and was modified
if [ -f "$TASK_GPKG" ]; then
    # Copy the GPKG to the export path so the host verifier can grab it
    # We copy it to a neutral location to avoid permission issues during copy_from_env
    cp "$TASK_GPKG" "$EXPORT_PATH"
    chmod 666 "$EXPORT_PATH"
    
    # Get file stats
    GPKG_SIZE=$(ls -l "$TASK_GPKG" | awk '{print $5}')
    echo "Exported GPKG size: $GPKG_SIZE"
else
    echo "ERROR: Task GeoPackage not found at $TASK_GPKG"
fi

# Create a simple JSON metadata file about the run (timestamps)
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "{\"task_start\": $TASK_START, \"task_end\": $TASK_END, \"gpkg_path\": \"$EXPORT_PATH\"}" > /sdcard/task_result.json
chmod 666 /sdcard/task_result.json

echo "=== Export Complete ==="