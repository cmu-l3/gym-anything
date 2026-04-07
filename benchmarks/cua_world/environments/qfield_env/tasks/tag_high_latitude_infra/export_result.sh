#!/system/bin/sh
# Export script for tag_high_latitude_infra
# Extracts the modified GeoPackage and verification metadata

echo "=== Exporting results ==="

PACKAGE="ch.opengis.qfield"
DEST_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
TASK_START_FILE="/sdcard/task_start_time.txt"

# 1. Force stop QField to ensure SQLite WAL journal is committed to main DB file
echo "Closing QField to commit database changes..."
am force-stop "$PACKAGE"
sleep 3

# 2. Capture final state screenshot (desktop/launcher view now, but useful for crash check)
screencap -p /sdcard/task_final.png

# 3. Check file timestamps
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
FILE_MODIFIED="false"

if [ -f "$DEST_GPKG" ]; then
    # Android stat format can vary, using simple comparison if possible
    # or just checking if it exists for now.
    # Ideally we compare modification time, but busybox stat might differ.
    FILE_MTIME=$(stat -c %Y "$DEST_GPKG" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    FILE_SIZE=$(stat -c %s "$DEST_GPKG" 2>/dev/null || echo "0")
else
    FILE_SIZE="0"
fi

# 4. Create result JSON
# We construct this manually in shell
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"file_exists\": true," >> /sdcard/task_result.json
echo "  \"file_modified\": $FILE_MODIFIED," >> /sdcard/task_result.json
echo "  \"file_size\": $FILE_SIZE," >> /sdcard/task_result.json
echo "  \"gpkg_path\": \"$DEST_GPKG\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result JSON created at /sdcard/task_result.json"

# 5. Ensure permissions for the host to pull files
chmod 666 /sdcard/task_result.json
chmod 666 "$DEST_GPKG" 2>/dev/null

echo "=== Export complete ==="