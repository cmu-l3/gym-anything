#!/system/bin/sh
# Export script for navigate_to_pharmacy_via_categories
# Runs inside the Android environment

echo "=== Exporting Results ==="

TASK_DIR="/sdcard/tasks/navigate_to_pharmacy_via_categories"
mkdir -p "$TASK_DIR"

# 1. Capture Final Screenshot
screencap -p "$TASK_DIR/final_state.png"
echo "Captured final screenshot"

# 2. Dump UI Hierarchy (XML)
# This helps the verifier check for text like "Pharmacy" or "Navigate" if VLM is ambiguous
uiautomator dump "$TASK_DIR/window_dump.xml" 2>/dev/null
echo "Dumped UI hierarchy"

# 3. Check if App is Running (Foreground)
APP_RUNNING="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.sygic.aura"; then
    APP_RUNNING="true"
fi

# 4. Get File Timestamps
TASK_START=$(cat "$TASK_DIR/task_start_time.txt" 2>/dev/null || echo "0")
NOW=$(date +%s)

# 5. Create JSON Result
# Note: JSON creation in Android shell is manual string construction
cat > "$TASK_DIR/task_result.json" <<EOF
{
  "task_start_timestamp": $TASK_START,
  "export_timestamp": $NOW,
  "app_running": $APP_RUNNING,
  "screenshot_path": "$TASK_DIR/final_state.png",
  "ui_dump_path": "$TASK_DIR/window_dump.xml"
}
EOF

# 6. Ensure permissions are open for the host to read
chmod 777 "$TASK_DIR/task_result.json"
chmod 777 "$TASK_DIR/final_state.png"
chmod 777 "$TASK_DIR/window_dump.xml" 2>/dev/null

echo "=== Export Complete ==="