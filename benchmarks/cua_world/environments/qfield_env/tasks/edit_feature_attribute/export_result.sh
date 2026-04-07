#!/system/bin/sh
echo "=== Exporting edit_feature_attribute result ==="

WORK_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
RESULT_FILE="/sdcard/task_result.json"
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# 1. Take final screenshot
screencap -p /sdcard/task_final.png

# 2. Force stop QField
# This ensures any WAL (Write-Ahead Logging) files are flushed to the main .gpkg file
echo "Stopping QField to flush database..."
am force-stop ch.opengis.qfield
sleep 2

# 3. Check File Modification
FILE_MODIFIED="false"
if [ -f "$WORK_GPKG" ]; then
    # Get modification time (epoch)
    MTIME=$(stat -c %Y "$WORK_GPKG" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$START_TIME" ]; then
        FILE_MODIFIED="true"
    fi
    FILE_SIZE=$(stat -c %s "$WORK_GPKG" 2>/dev/null || echo "0")
else
    FILE_SIZE="0"
fi

# 4. Query Database Content
FINAL_VALUE=""
if [ -f /system/bin/sqlite3 ] && [ -f "$WORK_GPKG" ]; then
    # Query the specific field we asked the agent to edit
    FINAL_VALUE=$(/system/bin/sqlite3 "$WORK_GPKG" "SELECT description FROM world_capitals WHERE name = 'Paris';" 2>/dev/null)
    echo "Retrieved value from DB: '$FINAL_VALUE'"
else
    echo "Cannot query database (missing file or sqlite3)"
fi

# 5. Create JSON Result
# We construct JSON manually since jq might not be on Android
# Escape quotes in the value
FINAL_VALUE_SAFE=$(echo "$FINAL_VALUE" | sed 's/"/\\"/g' | tr -d '\n')

echo "{
  \"task_start\": $START_TIME,
  \"task_end\": $END_TIME,
  \"file_modified\": $FILE_MODIFIED,
  \"file_exists\": true,
  \"file_size\": $FILE_SIZE,
  \"final_value\": \"$FINAL_VALUE_SAFE\"
}" > "$RESULT_FILE"

chmod 666 "$RESULT_FILE" 2>/dev/null

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="