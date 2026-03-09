#!/bin/bash
set -e
echo "=== Exporting disable_video_mirroring results ==="

source /workspace/scripts/task_utils.sh

# 1. Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot (CRITICAL for this task)
take_screenshot /tmp/task_final.png

# 3. Attempt to extract localStorage for secondary verification
# We try to dump the 'features/base/settings' key which often holds user prefs
echo "Attempting to extract Jitsi settings from localStorage..."
focus_firefox

# Open console
DISPLAY=:1 xdotool key F12
sleep 2
# Focus console input (may vary, but clicking bottom usually works)
# We'll use a keyboard shortcut to clear console first: Ctrl+L
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5

# Type JS to copy settings to clipboard
# We target 'features/base/settings'
JS_CMD="copy(localStorage.getItem('features/base/settings') || '{}')"
DISPLAY=:1 xdotool type --delay 20 "$JS_CMD"
DISPLAY=:1 xdotool key Return
sleep 1

# Save clipboard to file
DISPLAY=:1 xclip -o -selection clipboard > /tmp/jitsi_settings.json 2>/dev/null || echo "{}" > /tmp/jitsi_settings.json

# Close console
DISPLAY=:1 xdotool key F12
sleep 1

# 4. Check if Firefox is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "settings_dump_path": "/tmp/jitsi_settings.json"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"