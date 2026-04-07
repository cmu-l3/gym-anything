#!/system/bin/sh
echo "=== Exporting set_pedestrian_mode results ==="

PACKAGE="com.sygic.aura"
RESULT_FILE="/sdcard/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Check if app is running
APP_RUNNING="false"
if pidof $PACKAGE > /dev/null; then
    APP_RUNNING="true"
fi

# Attempt to read shared preferences for vehicle type (Best Effort)
# Note: This requires root or run-as access. 
# We try to grep for "pedestrian" or "vehicle" in shared prefs.
PREFS_CONTENT=""
if [ -d "/data/data/$PACKAGE/shared_prefs" ]; then
    # Try direct read (root)
    PREFS_CONTENT=$(grep -i "vehicle\|pedestrian\|routing" /data/data/$PACKAGE/shared_prefs/*.xml 2>/dev/null)
else
    # Try via run-as
    PREFS_CONTENT=$(run-as $PACKAGE cat shared_prefs/com.sygic.aura_preferences.xml 2>/dev/null | grep -i "vehicle\|pedestrian")
fi

# Sanitize prefs content for JSON (escape quotes and newlines)
SAFE_PREFS=$(echo "$PREFS_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create JSON result
echo "{" > $RESULT_FILE
echo "  \"task_start\": $TASK_START," >> $RESULT_FILE
echo "  \"task_end\": $TASK_END," >> $RESULT_FILE
echo "  \"app_running\": $APP_RUNNING," >> $RESULT_FILE
echo "  \"prefs_snippet\": \"$SAFE_PREFS\"," >> $RESULT_FILE
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"" >> $RESULT_FILE
echo "}" >> $RESULT_FILE

echo "Result saved to $RESULT_FILE"
chmod 666 $RESULT_FILE 2>/dev/null