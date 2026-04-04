#!/bin/bash
echo "=== Exporting Enforce Mandatory Patient Email Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_UOR=$(cat /tmp/initial_uor.txt 2>/dev/null || echo "-1")

# 1. Check Final Database State
# We look for the UOR value of the email field. 
# Expected: 2 (Required)
FINAL_UOR=$(librehealth_query "SELECT uor FROM layout_options WHERE field_id = 'email' AND form_id = 'DEM'" 2>/dev/null || echo "-1")
echo "Final UOR state: $FINAL_UOR"

# 2. Check Navigation/UI State (via Screenshots)
# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Firefox is still running (agent didn't crash it)
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_uor": $INITIAL_UOR,
    "final_uor": $FINAL_UOR,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="