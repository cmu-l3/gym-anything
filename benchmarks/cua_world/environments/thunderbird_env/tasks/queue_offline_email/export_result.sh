#!/bin/bash
echo "=== Exporting queue_offline_email result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TB_PROFILE="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${TB_PROFILE}/Mail/Local Folders"

# 1. Check Offline Mode preference
OFFLINE_MODE="false"
if grep -q 'user_pref("network.online", false);' "${TB_PROFILE}/prefs.js" 2>/dev/null; then
    OFFLINE_MODE="true"
fi

# 2. Safely copy mbox files to /tmp for the verifier to access via copy_from_env
cp "${LOCAL_MAIL_DIR}/Unsent Messages" /tmp/Unsent_Messages 2>/dev/null || touch /tmp/Unsent_Messages
cp "${LOCAL_MAIL_DIR}/Drafts" /tmp/Drafts 2>/dev/null || touch /tmp/Drafts
cp "${LOCAL_MAIL_DIR}/Sent" /tmp/Sent 2>/dev/null || touch /tmp/Sent

chmod 666 /tmp/Unsent_Messages /tmp/Drafts /tmp/Sent 2>/dev/null || true

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
INITIAL_UNSENT=$(cat /tmp/initial_unsent_count.txt 2>/dev/null || echo "0")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_unsent_count": $INITIAL_UNSENT,
    "offline_mode_active": $OFFLINE_MODE,
    "thunderbird_running": $(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="