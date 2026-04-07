#!/system/bin/sh
echo "=== Exporting plan_vor_route results ==="

PACKAGE="com.ds.avare"
PLAN_NAME="VOR_PRACTICE"
RESULT_JSON="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Check if App is running
APP_RUNNING="false"
if pidof $PACKAGE > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Search for the saved plan file
# Avare stores plans as JSON files, usually in internal storage, but accessible if we are root/system
# We search common locations.
PLAN_PATH=""
PLAN_CONTENT=""

# Location 1: Internal data
if [ -f "/data/data/com.ds.avare/files/plans/$PLAN_NAME" ]; then
    PLAN_PATH="/data/data/com.ds.avare/files/plans/$PLAN_NAME"
elif [ -f "/data/data/com.ds.avare/files/plans/$PLAN_NAME.json" ]; then
    PLAN_PATH="/data/data/com.ds.avare/files/plans/$PLAN_NAME.json"
# Location 2: External/Android data
elif [ -f "/sdcard/Android/data/com.ds.avare/files/plans/$PLAN_NAME" ]; then
    PLAN_PATH="/sdcard/Android/data/com.ds.avare/files/plans/$PLAN_NAME"
elif [ -f "/sdcard/Android/data/com.ds.avare/files/plans/$PLAN_NAME.json" ]; then
    PLAN_PATH="/sdcard/Android/data/com.ds.avare/files/plans/$PLAN_NAME.json"
fi

PLAN_EXISTS="false"
if [ -n "$PLAN_PATH" ]; then
    PLAN_EXISTS="true"
    # Read the plan content.
    # We copy it to a temp file on sdcard to ensure permissions for reading
    cp "$PLAN_PATH" /sdcard/exported_plan.json
    chmod 666 /sdcard/exported_plan.json
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$PLAN_PATH" 2>/dev/null || echo "0")
    TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    CREATED_DURING_TASK="false"
fi

# 4. Create Result JSON
echo "{" > $RESULT_JSON
echo "  \"app_running\": $APP_RUNNING," >> $RESULT_JSON
echo "  \"plan_exists\": $PLAN_EXISTS," >> $RESULT_JSON
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> $RESULT_JSON
echo "  \"plan_file_path\": \"$PLAN_PATH\"," >> $RESULT_JSON
echo "  \"exported_plan_path\": \"/sdcard/exported_plan.json\"," >> $RESULT_JSON
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"" >> $RESULT_JSON
echo "}" >> $RESULT_JSON

echo "=== Export complete ==="