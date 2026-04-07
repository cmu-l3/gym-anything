#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing Thunderbird
take_screenshot /tmp/task_final.png ga
sleep 1

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Close Thunderbird gracefully to ensure prefs.js is flushed to disk
echo "Closing Thunderbird to flush preferences..."
close_thunderbird
sleep 3

# Path to prefs.js
PROFILE_DIR="/home/ga/.thunderbird/default-release"
PREFS_FILE="$PROFILE_DIR/prefs.js"

# Check if prefs.js was modified during task
PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_prefs_mtime.txt 2>/dev/null || echo "0")

if [ "$PREFS_MTIME" -gt "$INITIAL_MTIME" ]; then
    PREFS_MODIFIED="true"
else
    PREFS_MODIFIED="false"
fi

# Use python to extract values from prefs.js
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 - <<EOF
import json
import re
import os

prefs_path = "$PREFS_FILE"
result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_modified": "$PREFS_MODIFIED" == "true",
    "app_was_running": "$APP_RUNNING" == "true",
    "prefs": {
        "mark_message_read_auto": None,
        "openMessageBehavior": None,
        "close_message_window_on_delete": None,
        "show_alert": None,
        "play_sound": None,
        "empty_trash_on_exit": None
    }
}

if os.path.exists(prefs_path):
    with open(prefs_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    def extract_pref(pref_name, is_bool=True):
        match = re.search(r'user_pref\("' + pref_name + r'",\s*(.*?)\);', content)
        if match:
            val = match.group(1).strip()
            if is_bool:
                return val.lower() == 'true'
            try:
                return int(val)
            except ValueError:
                return val
        return None
        
    result["prefs"]["mark_message_read_auto"] = extract_pref("mailnews.mark_message_read.auto", True)
    result["prefs"]["openMessageBehavior"] = extract_pref("mail.openMessageBehavior", False)
    result["prefs"]["close_message_window_on_delete"] = extract_pref("mail.close_message_window.on_delete", True)
    result["prefs"]["show_alert"] = extract_pref("mail.biff.show_alert", True)
    result["prefs"]["play_sound"] = extract_pref("mail.biff.play_sound", True)
    result["prefs"]["empty_trash_on_exit"] = extract_pref("mail.server.server1.empty_trash_on_exit", True)

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=4)
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="