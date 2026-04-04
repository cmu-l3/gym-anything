#!/system/bin/sh
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
DURATION=$((TASK_END - TASK_START))

# Capture final state screenshot
screencap -p /sdcard/task_final_state.png 2>/dev/null

# Check if app is in foreground
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
APP_VISIBLE="false"
if echo "$CURRENT_FOCUS" | grep -q "com.liverpooluni.ichartoncology"; then
    APP_VISIBLE="true"
fi

# Dump UI hierarchy (useful for debugging, though verification uses VLM)
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null || true

# Create JSON result
# We construct the JSON manually since 'jq' might not be available on Android
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"duration_seconds\": $DURATION," >> /sdcard/task_result.json
echo "  \"app_visible_at_end\": $APP_VISIBLE," >> /sdcard/task_result.json
echo "  \"final_screenshot_path\": \"/sdcard/task_final_state.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# Set permissions so host can read it
chmod 666 /sdcard/task_result.json 2>/dev/null

echo "Result saved to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="