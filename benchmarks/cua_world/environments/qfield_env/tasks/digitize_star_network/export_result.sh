#!/system/bin/sh
echo "=== Exporting digitize_star_network results ==="

# Define paths
WORK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_GPKG="/sdcard/task_result.gpkg"
PACKAGE="ch.opengis.qfield"

# 1. Force stop QField to ensure WAL (Write Ahead Log) is flushed to main DB file
am force-stop $PACKAGE
sleep 3

# 2. Copy GeoPackage to a staging location for extraction
# We copy it to /sdcard/task_result.gpkg which verifier will pull
cp "$WORK_GPKG" "$RESULT_GPKG"
chmod 666 "$RESULT_GPKG"

# 3. Check for file modification
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$WORK_GPKG" 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 4. Capture final screenshot
screencap -p /sdcard/task_final.png

# 5. Create basic result JSON (verifier will do heavy lifting with the DB)
cat > /sdcard/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "gpkg_path": "$RESULT_GPKG",
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Export complete. Result at /sdcard/task_result.json"