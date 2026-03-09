#!/system/bin/sh
# Export script for record_grazing_rotation_move task

echo "=== Exporting Task Results ==="

TASK_DIR="/sdcard/tasks/record_grazing_rotation_move"
RESULT_JSON="$TASK_DIR/task_result.json"
PACKAGE="org.farmos.app"

# 1. Capture Final Screenshot
screencap -p "$TASK_DIR/final_state.png"
echo "Final screenshot captured."

# 2. Dump UI Hierarchy (XML) - useful for text verification if needed
uiautomator dump "$TASK_DIR/final_ui.xml" 2>/dev/null
echo "UI hierarchy dumped."

# 3. Check if App is Running
APP_RUNNING="false"
if pidof org.farmos.app > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_DIR/task_start_time.txt" 2>/dev/null || echo "0")

# 5. Create Result JSON
# Note: Android shell usually has limited JSON tools, so we construct manually
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"app_was_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"final_screenshot_path\": \"$TASK_DIR/final_state.png\"," >> "$RESULT_JSON"
echo "  \"final_ui_path\": \"$TASK_DIR/final_ui.xml\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"

echo "=== Export Complete ==="