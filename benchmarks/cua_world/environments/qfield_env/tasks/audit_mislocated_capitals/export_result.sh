#!/system/bin/sh
# Export script for audit_mislocated_capitals task.
# Extracts the 'notes' field for the audited capitals to verified.

echo "=== Exporting task results ==="

GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_FILE="/sdcard/task_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# 1. Check if GeoPackage exists and was modified
if [ -f "$GPKG_TASK" ]; then
    GPKG_EXISTS="true"
    GPKG_SIZE=$(ls -l "$GPKG_TASK" | awk '{print $5}')
    # Simple modification check (file age) could be done here if needed
else
    GPKG_EXISTS="false"
    GPKG_SIZE="0"
fi

# 2. Extract data using sqlite3
# Output format: Name|Notes|Latitude|Longitude
echo "Extracting audit results..."
if [ "$GPKG_EXISTS" = "true" ]; then
    sqlite3 "$GPKG_TASK" "SELECT name, notes, latitude, longitude FROM world_capitals WHERE name IN ('Tokyo', 'Ottawa', 'Cairo', 'Canberra', 'Buenos Aires', 'London');" > "$RESULT_FILE"
else
    echo "ERROR: GeoPackage not found" > "$RESULT_FILE"
fi

# 3. Capture metadata
echo "--- METADATA ---" >> "$RESULT_FILE"
echo "timestamp=$(date +%s)" >> "$RESULT_FILE"
echo "gpkg_exists=$GPKG_EXISTS" >> "$RESULT_FILE"
echo "gpkg_size=$GPKG_SIZE" >> "$RESULT_FILE"

# 4. Check if QField is still running
if ps -A | grep -q "ch.opengis.qfield"; then
    echo "app_running=true" >> "$RESULT_FILE"
else
    echo "app_running=false" >> "$RESULT_FILE"
fi

# 5. Capture final screenshot (using screencap utility on Android)
screencap -p /sdcard/task_final.png

echo "Export complete. Results saved to $RESULT_FILE"
cat "$RESULT_FILE"