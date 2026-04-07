#!/system/bin/sh
# Export script for designate_mesh_hub task.
# Exports the modified GeoPackage for verification.

echo "=== Exporting Results ==="

TASK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
EXPORT_PATH="/sdcard/task_result.gpkg"
TASK_START_FILE="/sdcard/task_start_time.txt"

# Copy the GeoPackage to a location accessible for verification
cp "$TASK_GPKG" "$EXPORT_PATH"
chmod 644 "$EXPORT_PATH"

# Record file info
SIZE=$(stat -c %s "$EXPORT_PATH")
MTIME=$(stat -c %Y "$EXPORT_PATH")
START_TIME=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

echo "Exported GPKG size: $SIZE"

# Create result JSON
echo "{" > /sdcard/task_result.json
echo "  \"gpkg_path\": \"$EXPORT_PATH\"," >> /sdcard/task_result.json
echo "  \"size\": $SIZE," >> /sdcard/task_result.json
echo "  \"mtime\": $MTIME," >> /sdcard/task_result.json
echo "  \"start_time\": $START_TIME" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# Take final screenshot
screencap -p /sdcard/task_final.png

echo "=== Export Complete ==="