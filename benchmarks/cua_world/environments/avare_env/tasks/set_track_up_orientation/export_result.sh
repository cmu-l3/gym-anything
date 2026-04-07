#!/system/bin/sh
echo "=== Exporting set_track_up_orientation result ==="

# Paths
PREFS_FILE="/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"
TASK_START_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# 1. Take Final Screenshot
screencap -p "$FINAL_SCREENSHOT"

# 2. Read Task Start Time
TASK_START=0
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
fi

# 3. Analyze Preferences File
PREFS_EXISTS="false"
FILE_MODIFIED="false"
TRACK_UP_ENABLED="false"
FILE_SIZE=0

if [ -f "$PREFS_FILE" ]; then
    PREFS_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PREFS_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$PREFS_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check content for TrackUp="true"
    # The XML usually looks like: <boolean name="TrackUp" value="true" />
    if grep -q 'name="TrackUp" value="true"' "$PREFS_FILE"; then
        TRACK_UP_ENABLED="true"
    fi
fi

# 4. Check if App is Running
APP_RUNNING="false"
if pidof com.ds.avare > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON Result
# Note: Android shell usually doesn't have jq, so we manually construct JSON.
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"prefs_exists\": $PREFS_EXISTS," >> "$RESULT_JSON"
echo "  \"file_modified_during_task\": $FILE_MODIFIED," >> "$RESULT_JSON"
echo "  \"track_up_enabled\": $TRACK_UP_ENABLED," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$FINAL_SCREENSHOT\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="