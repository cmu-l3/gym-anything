#!/system/bin/sh
echo "=== Exporting Enable Speedometer Display results ==="

TASK_DIR="/sdcard/tasks/enable_speedometer_display"
PACKAGE="com.sygic.aura"

# 1. Record end time
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_DIR/task_start_time.txt" 2>/dev/null || echo "0")

# 2. Check if app is running
APP_RUNNING="false"
if pidof $PACKAGE > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# 3. Take final screenshot
screencap -p "$TASK_DIR/final_state.png"

# 4. Dump final UI hierarchy
# This is useful if the speedometer is a standard Android View
uiautomator dump "$TASK_DIR/final_ui.xml" 2>/dev/null || true

# 5. Check if screen changed (anti-gaming)
SCREEN_CHANGED="false"
if [ -f "$TASK_DIR/initial_state.png" ] && [ -f "$TASK_DIR/final_state.png" ]; then
    INIT_SIZE=$(stat -c%s "$TASK_DIR/initial_state.png" 2>/dev/null || echo "0")
    FINAL_SIZE=$(stat -c%s "$TASK_DIR/final_state.png" 2>/dev/null || echo "0")
    if [ "$INIT_SIZE" != "$FINAL_SIZE" ]; then
        SCREEN_CHANGED="true"
    fi
fi

# 6. Create result JSON
TEMP_JSON="$TASK_DIR/result.json"
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$TEMP_JSON"
echo "  \"screen_changed\": $SCREEN_CHANGED," >> "$TEMP_JSON"
echo "  \"initial_screenshot\": \"$TASK_DIR/initial_state.png\"," >> "$TEMP_JSON"
echo "  \"final_screenshot\": \"$TASK_DIR/final_state.png\"," >> "$TEMP_JSON"
echo "  \"final_ui_dump\": \"$TASK_DIR/final_ui.xml\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

echo "Result saved to $TEMP_JSON"
cat "$TEMP_JSON"
echo "=== Export complete ==="