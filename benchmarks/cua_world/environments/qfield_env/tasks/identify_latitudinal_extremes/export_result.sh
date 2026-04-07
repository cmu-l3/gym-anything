#!/system/bin/sh
# Export script for identify_latitudinal_extremes
# Prepares the GeoPackage for the host verifier

echo "=== Exporting identify_latitudinal_extremes results ==="

PACKAGE="ch.opengis.qfield"
WORK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
EXPORT_GPKG="/sdcard/task_result.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# 1. Force stop QField to flush WAL (Write-Ahead Log) to the main .gpkg file
# This is critical for SQLite databases on Android to ensure data is committed
echo "Stopping QField to flush database..."
am force-stop $PACKAGE
sleep 3

# 2. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 3. Copy the GeoPackage to a accessible location for extraction
# We copy it to /sdcard/task_result.gpkg which verifier.py will pull
if [ -f "$WORK_GPKG" ]; then
    cp "$WORK_GPKG" "$EXPORT_GPKG"
    chmod 644 "$EXPORT_GPKG"
    GPKG_EXISTS="true"
    GPKG_SIZE=$(stat -c %s "$EXPORT_GPKG" 2>/dev/null || echo "0")
else
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
    echo "ERROR: Working GeoPackage not found at $WORK_GPKG"
fi

# 4. Take a final screenshot for evidence
screencap -p /sdcard/task_final.png

# 5. Create a metadata JSON file
# Note: We can't use python inside Android easily to create JSON, so we echo string
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"gpkg_exists\": $GPKG_EXISTS," >> "$RESULT_JSON"
echo "  \"gpkg_size\": $GPKG_SIZE," >> "$RESULT_JSON"
echo "  \"gpkg_path\": \"$EXPORT_GPKG\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "=== Export complete ==="
cat "$RESULT_JSON"