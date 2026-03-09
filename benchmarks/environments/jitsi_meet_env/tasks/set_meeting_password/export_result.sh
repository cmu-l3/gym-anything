#!/bin/bash
set -e
echo "=== Exporting set_meeting_password results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
focus_firefox
sleep 1
DISPLAY=:1 xdotool mousemove 960 540  # Wake up toolbar
sleep 1
take_screenshot /tmp/task_final.png

# 2. Extract Data from Browser via JS Console Injection
# We inject JS to change the window title to the password value, then read it with wmctrl.
# This avoids needing a full browser driver.

echo "Injecting verification JavaScript..."
# Open Web Console (Ctrl+Shift+K in Firefox)
DISPLAY=:1 xdotool key ctrl+shift+k
sleep 3

# JS Verification Payload
# Reads APP.conference._room.room.password
JS_CMD="try { var pw = APP.conference._room.room.password; document.title = 'VERIFY_PW:' + (pw ? pw : 'NULL'); } catch(e) { document.title = 'VERIFY_PW:ERROR'; }"

# Type the command
DISPLAY=:1 xdotool type --clearmodifiers --delay 5 "$JS_CMD"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Read the window title
WINDOW_TITLES=$(DISPLAY=:1 wmctrl -l)
echo "Window titles found:"
echo "$WINDOW_TITLES"

# Close console (F12 or Ctrl+Shift+K again) to clean up view
DISPLAY=:1 xdotool key F12 2>/dev/null || true

# Extract password from title
DETECTED_PASSWORD="unknown"
if echo "$WINDOW_TITLES" | grep -q "VERIFY_PW:"; then
    # Extract text after VERIFY_PW:
    DETECTED_PASSWORD=$(echo "$WINDOW_TITLES" | grep -o "VERIFY_PW:.*" | head -1 | cut -d':' -f2-)
    # Clean up any trailing browser title text that might remain (though title set usually replaces all)
    # Usually document.title set replaces the whole window title prefix in Firefox
    DETECTED_PASSWORD=$(echo "$DETECTED_PASSWORD" | awk '{print $1}') # Take first word/token just in case
fi

echo "Detected Password from JS: $DETECTED_PASSWORD"

# 3. Backend Verification (Optional/Secondary)
# Check if we can see the password in the Prosody backend
# Prosody container name usually contains 'prosody'
PROSODY_CONTAINER=$(docker ps --format '{{.Names}}' | grep "prosody" | head -1 || echo "")
BACKEND_CONFIRMED="false"

if [ -n "$PROSODY_CONTAINER" ]; then
    echo "Checking backend container: $PROSODY_CONTAINER"
    # We can try to grep the prosody logs for room config changes
    # or just rely on the frontend check.
    # A simple robust check is hard via CLI without exact room internal ID.
    # We will log if the container is running.
    BACKEND_STATUS="running"
else
    BACKEND_STATUS="not_found"
fi

# 4. Anti-Gaming Timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "detected_password": "$DETECTED_PASSWORD",
    "backend_status": "$BACKEND_STATUS",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json