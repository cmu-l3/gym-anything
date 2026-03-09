#!/bin/bash
echo "=== Exporting optimize_autoreply_behavior result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

MAILBOX_ID=$(cat /tmp/target_mailbox_id.txt 2>/dev/null || echo "")
TARGET_EMAIL="facilities@helpdesk.local"

# If ID missing, try to find it
if [ -z "$MAILBOX_ID" ]; then
    MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='$TARGET_EMAIL' LIMIT 1" 2>/dev/null)
fi

echo "Checking configuration for Mailbox ID: $MAILBOX_ID"

MAILBOX_FOUND="false"
IS_ENABLED=""
IS_NEW=""
IS_REPLY=""
UPDATED_AT=""

if [ -n "$MAILBOX_ID" ]; then
    # Query the 3 relevant columns
    # Using specific query to ensure we get exact columns
    # is_auto_reply: Global toggle
    # is_auto_reply_new: Send to new conversations
    # is_auto_reply_reply: Send to replies
    RESULT=$(fs_query "SELECT is_auto_reply, is_auto_reply_new, is_auto_reply_reply, updated_at FROM mailboxes WHERE id=$MAILBOX_ID LIMIT 1" 2>/dev/null)
    
    if [ -n "$RESULT" ]; then
        MAILBOX_FOUND="true"
        IS_ENABLED=$(echo "$RESULT" | cut -f1)
        IS_NEW=$(echo "$RESULT" | cut -f2)
        IS_REPLY=$(echo "$RESULT" | cut -f3)
        UPDATED_AT=$(echo "$RESULT" | cut -f4)
    fi
fi

# Get task start time for anti-gaming check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_STATE=$(cat /tmp/initial_db_state.txt 2>/dev/null || echo "")

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mailbox_found": ${MAILBOX_FOUND},
    "mailbox_id": "${MAILBOX_ID}",
    "is_auto_reply": "${IS_ENABLED}",
    "is_auto_reply_new": "${IS_NEW}",
    "is_auto_reply_reply": "${IS_REPLY}",
    "updated_at": "${UPDATED_AT}",
    "task_start_timestamp": ${TASK_START},
    "initial_db_state": "${INITIAL_STATE}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="