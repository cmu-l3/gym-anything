#!/system/bin/sh
echo "=== Exporting RC Time Constant task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
screencap -p /sdcard/task_final_state.png 2>/dev/null || true

# Check if the app is currently in the foreground
# dumping window info and looking for package name
CURRENT_FOCUS=$(dumpsys window windows 2>/dev/null | grep -i "mCurrentFocus" || echo "unknown")
PACKAGE="com.hsn.electricalcalculations"

APP_RUNNING="false"
if echo "$CURRENT_FOCUS" | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
fi

# Create result JSON
# We use a temp file logic similar to Linux but adapted for Android shell (mksh)
RESULT_FILE="/sdcard/task_result.json"

echo "{" > $RESULT_FILE
echo "  \"task_start\": $TASK_START," >> $RESULT_FILE
echo "  \"task_end\": $TASK_END," >> $RESULT_FILE
echo "  \"app_running\": $APP_RUNNING," >> $RESULT_FILE
echo "  \"final_screenshot_path\": \"/sdcard/task_final_state.png\"" >> $RESULT_FILE
echo "}" >> $RESULT_FILE

echo "Result exported to $RESULT_FILE"
cat $RESULT_FILE
echo "=== Export complete ==="