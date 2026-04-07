#!/system/bin/sh
echo "=== Exporting map_hazard_offset results ==="

# Define paths
PACKAGE="ch.opengis.qfield"
GPKG_WORK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
OUTPUT_GPKG="/sdcard/task_output.gpkg"
JSON_RESULT="/sdcard/task_result.json"

# 1. Force stop QField
# This is CRITICAL to ensure the SQLite WAL (Write-Ahead Log) is flushed to the main file
echo "Stopping QField to flush database..."
am force-stop $PACKAGE
sleep 2

# 2. Capture final screenshot
screencap -p /sdcard/task_final.png

# 3. Copy the GeoPackage to a staging area for the verifier
# We copy it to ensuring we don't lock the app's file
if [ -f "$GPKG_WORK" ]; then
    cp "$GPKG_WORK" "$OUTPUT_GPKG"
    chmod 666 "$OUTPUT_GPKG"
    echo "GeoPackage exported to $OUTPUT_GPKG"
    GPKG_EXISTS="true"
    GPKG_SIZE=$(stat -c %s "$OUTPUT_GPKG")
else
    echo "ERROR: GeoPackage not found at $GPKG_WORK"
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
fi

# 4. Read timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Create metadata JSON
# We write this to a file that the verifier will pull
echo "{" > "$JSON_RESULT"
echo "  \"task_start\": $TASK_START," >> "$JSON_RESULT"
echo "  \"task_end\": $TASK_END," >> "$JSON_RESULT"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$JSON_RESULT"
echo "  \"gpkg_size\": $GPKG_SIZE," >> "$JSON_RESULT"
echo "  \"gpkg_path_in_container\": \"$OUTPUT_GPKG\"" >> "$JSON_RESULT"
echo "}" >> "$JSON_RESULT"

echo "Metadata saved to $JSON_RESULT"
cat "$JSON_RESULT"

echo "=== Export complete ==="