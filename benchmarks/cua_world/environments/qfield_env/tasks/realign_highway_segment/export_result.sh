#!/system/bin/sh
# export_result.sh for realign_highway_segment
# Captures the state of the GeoPackage and screenshots for verification.

echo "=== Exporting results ==="

PACKAGE="ch.opengis.qfield"
DATA_DIR="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets"
GPKG="$DATA_DIR/world_survey.gpkg"
RESULT_JSON="/data/local/tmp/task_result.json"
FINAL_SCREENSHOT="/data/local/tmp/final_state.png"
TASK_START_FILE="/data/local/tmp/task_start_time.txt"

# 1. Capture Screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Check File Stats
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
GPKG_MTIME=$(stat -c %Y "$GPKG" 2>/dev/null || echo "0")
GPKG_SIZE=$(stat -c %s "$GPKG" 2>/dev/null || echo "0")

MODIFIED_DURING_TASK="false"
if [ "$GPKG_MTIME" -ge "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# 3. Extract Data from GeoPackage using sqlite3
# We need to verify if the feature has > 2 vertices and if one is near Niamey.
# Since we can't easily do complex spatial math in shell, we'll export the geometry blob hex
# and let the python verifier handle the parsing.

# Get the geometry blob in hex for the target feature
GEOM_HEX=$(sqlite3 "$GPKG" "SELECT quote(geom) FROM highway_segments WHERE name='Trans-African Hwy 2';" 2>/dev/null)
# Clean up the output (sqlite quote returns X'...' string, we just want the hex inside)
GEOM_HEX=${GEOM_HEX#*\'} # Remove leading X'
GEOM_HEX=${GEOM_HEX%\'*} # Remove trailing '

# Get vertex count (hacky approximation or just rely on blob length in python)
# We will just export the hex.

# 4. Check if QField is running
APP_RUNNING=$(pidof $PACKAGE > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
cat > "$RESULT_JSON" <<EOF
{
    "task_start": $TASK_START,
    "gpkg_mtime": $GPKG_MTIME,
    "gpkg_size_bytes": $GPKG_SIZE,
    "file_modified": $MODIFIED_DURING_TASK,
    "geom_hex": "$GEOM_HEX",
    "app_running": $APP_RUNNING,
    "screenshot_path": "$FINAL_SCREENSHOT"
}
EOF

# 6. Copy files to /sdcard/tasks/realign_highway_segment/ (or a mounted volume) if needed
# But usually the verifier 'copy_from_env' pulls from the container paths.
# We'll leave them in /data/local/tmp for easy access if the user has root,
# but for standard non-root access, putting them in /sdcard is safer.
cp "$RESULT_JSON" "/sdcard/task_result.json"
cp "$FINAL_SCREENSHOT" "/sdcard/task_final.png"

echo "Export complete. Result at /sdcard/task_result.json"