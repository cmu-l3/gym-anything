#!/bin/bash
set -e
echo "=== Exporting configure_notification_sounds result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Meeting URL (to verify they joined the correct room)
focus_firefox
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool key ctrl+c
sleep 0.5
CURRENT_URL=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null || echo "")
# Clear selection
DISPLAY=:1 xdotool key Escape

# 3. Extract Jitsi Settings via Console -> Clipboard
# We access the Redux store to get the exact boolean states of the settings
echo "Extracting settings from browser..."

# Open Console
DISPLAY=:1 xdotool key F12
sleep 2
DISPLAY=:1 xdotool key ctrl+shift+k  # Focus console in Firefox
sleep 1

# Command to copy settings to clipboard
# We use 'copy()' which is available in Firefox console
JS_CMD='copy(JSON.stringify(APP.store.getState()["features/base/settings"]))'
DISPLAY=:1 xdotool type --clearmodifiers --delay 5 "$JS_CMD"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 1

# Read clipboard to file
SETTINGS_JSON=$(DISPLAY=:1 xclip -selection clipboard -o 2>/dev/null || echo "{}")
echo "$SETTINGS_JSON" > /tmp/extracted_settings.json

# Close Console
DISPLAY=:1 xdotool key F12
sleep 1

# 4. Check if agent took the requested screenshot
AGENT_SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_sounds_final.png" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "final_url": "$CURRENT_URL",
    "settings": $SETTINGS_JSON,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="