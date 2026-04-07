#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot (Evidence)
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if Application is Running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Check for any user-saved screenshots (optional evidence)
# Agents might use the built-in screenshot button
USER_SCREENSHOT_COUNT=$(find /home/ga/Documents/OpenBCI_GUI/Screenshots -name "*.png" -newermt "@$TASK_START" 2>/dev/null | wc -l)

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "user_screenshots_created": $USER_SCREENSHOT_COUNT,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="