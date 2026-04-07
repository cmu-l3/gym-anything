#!/system/bin/sh
# Export script for classify_island_capitals task

echo "=== Exporting classify_island_capitals results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
PACKAGE="ch.opengis.qfield"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check if App was running
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 3. Prepare Result Artifacts
# We copy the modified GeoPackage to a known location for the verifier to pull
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
EXPORT_GPKG="/sdcard/task_result.gpkg"

GPKG_EXISTS="false"
GPKG_MODIFIED="false"

if [ -f "$GPKG_PATH" ]; then
    GPKG_EXISTS="true"
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$GPKG_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        GPKG_MODIFIED="true"
    fi
    
    # Copy to export path (readable by adb pull / copy_from_env)
    cp "$GPKG_PATH" "$EXPORT_GPKG"
    chmod 666 "$EXPORT_GPKG"
fi

# 4. Create JSON Summary (internal)
cat > /sdcard/task_result_summary.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "gpkg_exists": $GPKG_EXISTS,
    "gpkg_modified": $GPKG_MODIFIED,
    "gpkg_path": "$EXPORT_GPKG"
}
EOF

echo "Export complete. Result GPGK at $EXPORT_GPKG"