#!/bin/bash
echo "=== Exporting Dual Band Power Asymmetry Result ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the user's expected screenshot exists
USER_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/asymmetry_setup.png"
USER_SCREENSHOT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$USER_SCREENSHOT" ]; then
    USER_SCREENSHOT_EXISTS="true"
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$USER_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if App is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 3. Take final system screenshot for VLM verification
# This is the "ground truth" view of the desktop
echo "Capturing final system state..."
take_screenshot /tmp/task_final.png

# 4. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "user_screenshot_created_during_task": $FILE_CREATED_DURING_TASK,
    "user_screenshot_path": "$USER_SCREENSHOT",
    "app_was_running": $APP_RUNNING,
    "system_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="