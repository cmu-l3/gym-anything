#!/system/bin/sh
echo "=== Exporting digitize_cable_route results ==="

# Define paths
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /sdcard/initial_count.txt 2>/dev/null || echo "0")

# 1. Take final screenshot for VLM verification
screencap -p /sdcard/task_final.png

# 2. Check if file exists and get stats
if [ -f "$GPKG_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(ls -l "$GPKG_PATH" | awk '{print $5}')
    FILE_MTIME=$(stat -c %Y "$GPKG_PATH" 2>/dev/null || echo "0")
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
fi

# 3. Check modification time vs task start (Anti-gaming)
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
else
    MODIFIED_DURING_TASK="false"
fi

# 4. Create simple JSON report
# We don't verify the DB content here because doing complex SQL/binary parsing in shell is hard.
# We will copy the GPKG to the host in verifier.py and analyze it there.
cat > /sdcard/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "gpkg_path_container": "$GPKG_PATH",
    "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Export complete. Result at /sdcard/task_result.json"