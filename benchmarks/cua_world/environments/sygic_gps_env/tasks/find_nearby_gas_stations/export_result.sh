#!/system/bin/sh
echo "=== Exporting find_nearby_gas_stations results ==="

EXPORT_DIR="/sdcard/task_verification"
mkdir -p "$EXPORT_DIR" 2>/dev/null

# 1. Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
echo "$TASK_END" > "$EXPORT_DIR/task_end_time.txt"

# 2. Capture final screenshot
screencap -p "$EXPORT_DIR/final_screenshot.png" 2>/dev/null

# 3. Dump UI Hierarchy (XML) - Critical for text analysis
uiautomator dump "$EXPORT_DIR/ui_dump.xml" 2>/dev/null || echo "UI dump failed"

# 4. Dump Activity Stack - To verify we are not on the launcher
dumpsys activity activities | grep -E "mResumedActivity|mFocusedActivity" | head -n 5 > "$EXPORT_DIR/activity_stack.txt" 2>/dev/null

# 5. Check if app is running
if dumpsys window windows | grep -q "com.sygic.aura"; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 6. Create result JSON
# We use a temp file strategy to avoid shell JSON escaping hell
cat > "$EXPORT_DIR/task_result.json" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_running": $APP_RUNNING,
  "final_screenshot_path": "$EXPORT_DIR/final_screenshot.png",
  "ui_dump_path": "$EXPORT_DIR/ui_dump.xml",
  "activity_stack_path": "$EXPORT_DIR/activity_stack.txt"
}
EOF

echo "=== Export complete ==="