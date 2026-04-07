#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot (Critical for VLM)
echo "Capturing final state..."
if type take_screenshot >/dev/null 2>&1; then
    take_screenshot /tmp/task_final.png
else
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || true
fi

# 2. Check Application State
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

# 4. Save to final location with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="