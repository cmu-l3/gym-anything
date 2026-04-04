#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting send_chat_message results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png
sleep 1

# ── Attempt to extract chat content via DOM Scraping ───────────────────────
# We will use xdotool to open the developer console, run JS, and copy output.
# This serves as a secondary verification signal alongside VLM.

echo "Attempting to scrape chat content..."
focus_firefox
sleep 1

# Open Web Console (Ctrl+Shift+K in Firefox)
DISPLAY=:1 xdotool key ctrl+shift+k
sleep 3

# JS command to extract chat messages
# Jitsi classes change, so we look for generic chat-related class partials
JS_CMD='console.log("JSON_DUMP:" + JSON.stringify(Array.from(document.querySelectorAll("[class*=\"message\"], [class*=\"text\"]")).map(el => el.innerText).filter(t => t.length > 0)))'

# Type the command
DISPLAY=:1 xdotool type --clearmodifiers --delay 5 "$JS_CMD"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Select all in console and copy (flaky, but worth a try for text signal)
DISPLAY=:1 xdotool key ctrl+a
sleep 0.5
DISPLAY=:1 xdotool key ctrl+c
sleep 0.5

# Save clipboard to file
DISPLAY=:1 xclip -o -selection clipboard > /tmp/console_dump.txt 2>/dev/null || true
echo "Console dump saved (bytes: $(stat -c %s /tmp/console_dump.txt 2>/dev/null || echo 0))"

# Close dev tools (F12)
DISPLAY=:1 xdotool key F12 2>/dev/null || true
sleep 1

# Check if Jitsi/Firefox is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# ── Create Result JSON ───────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "console_dump_path": "/tmp/console_dump.txt",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json