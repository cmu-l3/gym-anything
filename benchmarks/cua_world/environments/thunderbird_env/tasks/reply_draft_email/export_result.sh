#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Give Thunderbird a moment to flush any pending disk writes
sleep 2

# Check if application was running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

# Get final counts
FINAL_DRAFT_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Drafts" 2>/dev/null || echo "0")
FINAL_SENT_COUNT=$(grep -c "^From " "${LOCAL_MAIL_DIR}/Sent" 2>/dev/null || echo "0")
INITIAL_DRAFT_COUNT=$(cat /tmp/initial_draft_count.txt 2>/dev/null || echo "0")
INITIAL_SENT_COUNT=$(cat /tmp/initial_sent_count.txt 2>/dev/null || echo "0")

# Copy mbox files to /tmp for easy verifier access (avoids permission issues)
cp "${LOCAL_MAIL_DIR}/Drafts" /tmp/Drafts.mbox 2>/dev/null || touch /tmp/Drafts.mbox
cp "${LOCAL_MAIL_DIR}/Sent" /tmp/Sent.mbox 2>/dev/null || touch /tmp/Sent.mbox
chmod 666 /tmp/Drafts.mbox /tmp/Sent.mbox

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_draft_count": $INITIAL_DRAFT_COUNT,
    "final_draft_count": $FINAL_DRAFT_COUNT,
    "initial_sent_count": $INITIAL_SENT_COUNT,
    "final_sent_count": $FINAL_SENT_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="