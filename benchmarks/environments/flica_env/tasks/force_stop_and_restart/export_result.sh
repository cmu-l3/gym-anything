#!/system/bin/sh
echo "=== Exporting force_stop_and_restart results ==="

PACKAGE="com.robert.fcView"

# 1. Get Final Process ID
FINAL_PID=$(pidof $PACKAGE)
# If app is not running, FINAL_PID will be empty
if [ -z "$FINAL_PID" ]; then
    FINAL_PID_VAL="null"
    APP_RUNNING="false"
else
    FINAL_PID_VAL="$FINAL_PID"
    APP_RUNNING="true"
fi

# 2. Get Initial PID
INITIAL_PID=$(cat /sdcard/initial_pid.txt 2>/dev/null || echo "null")

# 3. Timestamp checks
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 5. Create JSON Result
# Note: Android shell usually has limited JSON tools, constructing manually
JSON_PATH="/sdcard/task_result.json"

echo "{" > $JSON_PATH
echo "  \"initial_pid\": \"$INITIAL_PID\"," >> $JSON_PATH
echo "  \"final_pid\": \"$FINAL_PID_VAL\"," >> $JSON_PATH
echo "  \"app_running\": $APP_RUNNING," >> $JSON_PATH
echo "  \"task_start\": $TASK_START," >> $JSON_PATH
echo "  \"task_end\": $TASK_END," >> $JSON_PATH
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> $JSON_PATH
echo "}" >> $JSON_PATH

echo "Result exported to $JSON_PATH"
cat $JSON_PATH
echo "=== Export complete ==="