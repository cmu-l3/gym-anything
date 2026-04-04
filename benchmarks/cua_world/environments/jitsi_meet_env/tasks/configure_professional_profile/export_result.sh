#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JSON_OUTPUT="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# We need to extract the internal state from the browser to verify:
# 1. Display Name
# 2. Email (persisted in localStorage)
# 3. Audio/Video Mute state
# 4. That we are actually IN the meeting (not still on pre-join)

echo "Extracting Jitsi state via Firefox console..."

focus_firefox
sleep 1

# Open Console (Ctrl+Shift+K)
DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+k
sleep 2

# Clear console (Ctrl+L) to be safe
DISPLAY=:1 xdotool key --clearmodifiers ctrl+l
sleep 1

# Inject JS to extract state and copy to clipboard
# We use a compact one-liner to avoid typing issues.
# We check:
# - APP.conference.getLocalDisplayName()
# - APP.conference.isLocalAudioMuted()
# - APP.conference.isLocalVideoMuted()
# - localStorage content for email
# - Room name to ensure we joined

JS_COMMAND='
var res = {
  in_meeting: (typeof APP !== "undefined" && APP.conference && APP.conference.isJoined()),
  display_name: (typeof APP !== "undefined" && APP.conference) ? APP.conference.getLocalDisplayName() : null,
  audio_muted: (typeof APP !== "undefined" && APP.conference) ? APP.conference.isLocalAudioMuted() : null,
  video_muted: (typeof APP !== "undefined" && APP.conference) ? APP.conference.isLocalVideoMuted() : null,
  local_storage: localStorage.getItem("jitsiLocalStorage")
};
copy(JSON.stringify(res));
'

# Type the command
# We use xclip to put the command on the clipboard, then paste it into the console, 
# because typing long strings with xdotool is slow and error-prone.
echo "$JS_COMMAND" | xclip -selection clipboard
DISPLAY=:1 xdotool key --clearmodifiers ctrl+v
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Now the result should be in the clipboard (thanks to copy() function in Firefox console)
# Dump clipboard to file
xclip -selection clipboard -o > "$JSON_OUTPUT" 2>/dev/null || echo "{}" > "$JSON_OUTPUT"

# Close console (F12 or Ctrl+Shift+K again)
DISPLAY=:1 xdotool key --clearmodifiers F12 2>/dev/null || true

# Validate if we got valid JSON
if ! jq -e . "$JSON_OUTPUT" >/dev/null 2>&1; then
    echo "Failed to extract valid JSON from browser."
    echo "{}" > "$JSON_OUTPUT"
fi

# Add timestamp info to the result
jq --arg start "$TASK_START" '. + {task_start_time: $start}' "$JSON_OUTPUT" > "${JSON_OUTPUT}.tmp" && mv "${JSON_OUTPUT}.tmp" "$JSON_OUTPUT"

echo "Extracted State:"
cat "$JSON_OUTPUT"

echo "=== Export complete ==="