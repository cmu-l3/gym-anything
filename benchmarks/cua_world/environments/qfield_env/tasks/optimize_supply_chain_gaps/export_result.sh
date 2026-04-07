#!/system/bin/sh
echo "=== Exporting optimize_supply_chain_gaps result ==="

# Define paths
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
TASK_START_FILE="/sdcard/task_start_time.txt"

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Get Task Timing
TASK_END=$(date +%s)
TASK_START=0
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
fi

# 3. Check File Status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$GPKG_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$GPKG_PATH")
    FILE_MTIME=$(stat -c %Y "$GPKG_PATH")
    
    # Check if modified after start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Check App Status
APP_RUNNING=$(pidof ch.opengis.qfield > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
# We write to a temporary JSON file that the verifier will pull
RESULT_JSON="/sdcard/task_result.json"

cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gpkg_exists": $FILE_EXISTS,
    "gpkg_modified": $FILE_MODIFIED,
    "gpkg_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "gpkg_path_in_container": "$GPKG_PATH"
}
EOF

# 6. Prepare Files for Extraction
# The verifier uses copy_from_env. We need to ensure the GPKG is readable.
# It is already in /sdcard which is usually readable, but let's copy to a staging area just in case
# specifically for the verifier to pull.
cp "$GPKG_PATH" /sdcard/result_world_survey.gpkg
chmod 666 /sdcard/result_world_survey.gpkg

echo "Result JSON saved to $RESULT_JSON"
echo "Result GPKG staged at /sdcard/result_world_survey.gpkg"
echo "=== Export Complete ==="