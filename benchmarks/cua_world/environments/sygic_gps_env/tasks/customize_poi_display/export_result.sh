#!/system/bin/sh
# Export script for customize_poi_display task
# Runs inside the Android environment

echo "=== Exporting customize_poi_display results ==="

TASK_DIR="/sdcard/tasks/customize_poi_display"
RESULT_JSON="$TASK_DIR/task_result.json"

# 1. Capture final state screenshot (system level)
screencap -p "$TASK_DIR/final_state.png"

# 2. Check for agent-provided confirmation screenshot
CONFIRMATION_EXISTS="false"
if [ -f "$TASK_DIR/poi_config_done.png" ]; then
    CONFIRMATION_EXISTS="true"
fi

# 3. Check timestamps to ensure work was done during task
TASK_START=$(cat "$TASK_DIR/task_start_time.txt" 2>/dev/null || echo "0")
NOW=$(date +%s)

# 4. Dump UI hierarchy (optional helper for verification if VLM fails)
uiautomator dump "$TASK_DIR/ui_dump.xml" 2>/dev/null

# 5. Create JSON result
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $NOW," >> "$RESULT_JSON"
echo "  \"confirmation_screenshot_exists\": $CONFIRMATION_EXISTS," >> "$RESULT_JSON"
echo "  \"final_screenshot_path\": \"$TASK_DIR/final_state.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"