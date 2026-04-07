#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Copy the mbox files to /tmp for the verifier to safely retrieve
rm -f /tmp/Drafts.mbox /tmp/Sent.mbox 2>/dev/null
if [ -f "${LOCAL_MAIL_DIR}/Drafts" ]; then
    cp "${LOCAL_MAIL_DIR}/Drafts" /tmp/Drafts.mbox
    chmod 666 /tmp/Drafts.mbox
    DRAFTS_MTIME=$(stat -c %Y /tmp/Drafts.mbox 2>/dev/null || echo "0")
    if [ "$DRAFTS_MTIME" -gt "$TASK_START" ]; then
        DRAFTS_MODIFIED="true"
    else
        DRAFTS_MODIFIED="false"
    fi
else
    DRAFTS_MODIFIED="false"
fi

if [ -f "${LOCAL_MAIL_DIR}/Sent" ]; then
    cp "${LOCAL_MAIL_DIR}/Sent" /tmp/Sent.mbox
    chmod 666 /tmp/Sent.mbox
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drafts_modified_during_task": $DRAFTS_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="