#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot showing final state of Thunderbird
take_screenshot /tmp/task_final.png

# Close Thunderbird gracefully so it flushes all mbox file changes to disk
close_thunderbird
sleep 3

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

BUDGET_FOLDER="${LOCAL_MAIL_DIR}/Budget_Reviews"
INBOX_FOLDER="${LOCAL_MAIL_DIR}/Inbox"

# Copy mbox files to /tmp for safe extraction by the python verifier
cp "$BUDGET_FOLDER" /tmp/result_budget_reviews_mbox 2>/dev/null || touch /tmp/result_budget_reviews_mbox
cp "$INBOX_FOLDER" /tmp/result_inbox_mbox 2>/dev/null || touch /tmp/result_inbox_mbox

# Set wide open permissions to ensure verifier can retrieve them
chmod 666 /tmp/result_budget_reviews_mbox /tmp/result_inbox_mbox

# Retrieve basic stats for programmatic fast-fail validation
if [ -f "$BUDGET_FOLDER" ]; then
    BUDGET_MTIME=$(stat -c %Y "$BUDGET_FOLDER" 2>/dev/null || echo "0")
    BUDGET_SIZE=$(stat -c %s "$BUDGET_FOLDER" 2>/dev/null || echo "0")
    if [ "$BUDGET_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    else
        FILE_MODIFIED_DURING_TASK="false"
    fi
else
    BUDGET_MTIME="0"
    BUDGET_SIZE="0"
    FILE_MODIFIED_DURING_TASK="false"
fi

# Store all parameters in a simple JSON to be copied out
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "budget_mbox_size": $BUDGET_SIZE,
    "budget_mbox_mtime": $BUDGET_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Carefully move json into place to avoid permission errors
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json