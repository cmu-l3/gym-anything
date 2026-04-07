#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Record task end time and reference start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check for the user-generated screenshot (Primary Deliverable)
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/left_hemi_montage.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if OpenBCI is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 4. Capture Final System State Screenshot (for VLM verification of the actual GUI state)
# This serves as a backup if the user didn't save their screenshot, and verifies the live state.
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "user_screenshot_exists": $SCREENSHOT_EXISTS,
    "user_screenshot_valid_time": $SCREENSHOT_CREATED_DURING_TASK,
    "user_screenshot_size": $SCREENSHOT_SIZE,
    "user_screenshot_path": "$EXPECTED_SCREENSHOT",
    "final_state_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="