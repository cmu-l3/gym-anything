#!/system/bin/sh
echo "=== Exporting Restore Vandalized Capital Names results ==="

GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Check file statistics
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"

if [ -f "$GPKG_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$GPKG_PATH")
    FILE_MTIME=$(stat -c %Y "$GPKG_PATH")
fi

# 3. Check if app is running
APP_RUNNING="false"
if ps -A | grep -q "ch.opengis.qfield"; then
    APP_RUNNING="true"
fi

# 4. Create result JSON
# We don't analyze the DB here because we want to do it securely in the verifier.
# We just export the file and metadata.
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "app_running": $APP_RUNNING,
    "gpkg_path": "$GPKG_PATH"
}
EOF

# 5. Copy the GeoPackage to a temp location with a fixed name for easier retrieval
# (The verifier will pull this file)
cp "$GPKG_PATH" /sdcard/output_world_survey.gpkg
chmod 644 /sdcard/output_world_survey.gpkg

echo "Export complete. Result saved to $RESULT_JSON"