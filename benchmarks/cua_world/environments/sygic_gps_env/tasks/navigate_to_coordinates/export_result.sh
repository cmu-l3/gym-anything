#!/system/bin/sh
echo "=== Exporting navigate_to_coordinates results ==="

PACKAGE="com.sygic.aura"
TASK_DIR="/sdcard/tasks/navigate_to_coordinates"
RESULT_JSON="/sdcard/task_result.json"

# 1. Record end time
END_TIME=$(date +%s)
START_TIME=$(cat "$TASK_DIR/start_time.txt" 2>/dev/null || echo "0")

# 2. Check if app is running (Agent shouldn't have crashed it)
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 3. Capture final screenshot for verification
screencap -p "$TASK_DIR/final_state.png"

# 4. Dump UI hierarchy (Optional secondary signal)
# Note: uiautomator dump can fail on some Android versions/states, so we ignore errors
uiautomator dump "$TASK_DIR/final_ui.xml" > /dev/null 2>&1

# 5. Create JSON result
# Using echo to construct JSON since jq might not be available on Android shell
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $START_TIME," >> "$RESULT_JSON"
echo "  \"task_end\": $END_TIME," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"final_screenshot_path\": \"$TASK_DIR/final_state.png\"," >> "$RESULT_JSON"
echo "  \"ui_dump_path\": \"$TASK_DIR/final_ui.xml\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"