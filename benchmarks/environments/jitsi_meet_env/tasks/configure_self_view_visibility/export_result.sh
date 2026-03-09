#!/bin/bash
set -e
echo "=== Exporting configure_self_view_visibility result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract LocalStorage state via Firefox Developer Console
# This is a robust way to get internal app state without Selenium
echo "Extracting Jitsi settings from browser..."

focus_firefox
sleep 1

# Open Developer Tools Console (Ctrl+Shift+K)
DISPLAY=:1 xdotool key ctrl+shift+k
sleep 3

# Focus console input (usually auto-focused, but click to be safe)
# Coordinates depend on dev tools position, but typing usually works if docked bottom
# We'll assume standard layout. Ctrl+L clears console.
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5

# Type JS command to copy settings to clipboard
# We use copy() which is a standard DevTools function
JS_COMMAND="copy(localStorage.getItem('features/base/settings'))"
DISPLAY=:1 xdotool type --delay 10 "$JS_COMMAND"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 1

# Extract clipboard content to file
EXTRACTED_SETTINGS_FILE="/tmp/jitsi_settings.json"
# Try xclip (installed in env)
if command -v xclip >/dev/null; then
    DISPLAY=:1 xclip -o -selection clipboard > "$EXTRACTED_SETTINGS_FILE" 2>/dev/null || echo "{}" > "$EXTRACTED_SETTINGS_FILE"
else
    echo "{}" > "$EXTRACTED_SETTINGS_FILE"
fi

# Close Dev Tools (F12)
DISPLAY=:1 xdotool key F12
sleep 1

# 3. Check if camera is active (using xdotool to check title or visual implies it)
# We'll rely on VLM for visual confirmation of camera state, but can check title
WINDOW_TITLE=$(get_firefox_window_id | xargs -I{} DISPLAY=:1 xdotool getwindowname {} 2>/dev/null || echo "")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Check if settings file is valid JSON
if ! jq -e . "$EXTRACTED_SETTINGS_FILE" >/dev/null 2>&1; then
    echo "Warning: Extracted settings are not valid JSON or empty"
    echo "{}" > "$EXTRACTED_SETTINGS_FILE"
fi

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "window_title": "$(echo "$WINDOW_TITLE" | sed 's/"/\\"/g')",
    "jitsi_settings": $(cat "$EXTRACTED_SETTINGS_FILE"),
    "settings_extracted": $([ -s "$EXTRACTED_SETTINGS_FILE" ] && echo "true" || echo "false")
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Cleanup
rm -f "$TEMP_JSON" "$EXTRACTED_SETTINGS_FILE"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="