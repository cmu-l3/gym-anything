#!/bin/bash
echo "=== Exporting mark_conversation_spam result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Get tracked IDs
CONV_ID=$(cat /tmp/task_conversation_id.txt 2>/dev/null)
MAILBOX_ID=$(cat /tmp/task_mailbox_id.txt 2>/dev/null)

if [ -z "$CONV_ID" ]; then
    echo "ERROR: Conversation ID not found"
    CONV_FOUND="false"
else
    CONV_FOUND="true"
fi

# Query current state of the conversation
# FreeScout Status codes: 1=Active, 2=Pending, 3=Closed, 4=Spam
# Folder types: 1=Unassigned, 2=Mine, 3=Drafts, 4=Assigned, 5=Spam, 6=Closed/Trash?
CURRENT_STATE=$(fs_query "SELECT status, folder_id, UNIX_TIMESTAMP(updated_at) FROM conversations WHERE id = $CONV_ID" 2>/dev/null)

CURRENT_STATUS=""
CURRENT_FOLDER_ID=""
UPDATED_AT_UNIX="0"
FOLDER_TYPE=""

if [ -n "$CURRENT_STATE" ]; then
    CURRENT_STATUS=$(echo "$CURRENT_STATE" | cut -f1)
    CURRENT_FOLDER_ID=$(echo "$CURRENT_STATE" | cut -f2)
    UPDATED_AT_UNIX=$(echo "$CURRENT_STATE" | cut -f3)

    # Get the type of the folder the conversation is currently in
    if [ -n "$CURRENT_FOLDER_ID" ]; then
        FOLDER_TYPE=$(fs_query "SELECT type FROM folders WHERE id = $CURRENT_FOLDER_ID" 2>/dev/null)
    fi
fi

# Check if updated during task
WAS_UPDATED_DURING_TASK="false"
if [ "$UPDATED_AT_UNIX" -gt "$TASK_START" ]; then
    WAS_UPDATED_DURING_TASK="true"
fi

# Get the official Spam folder ID for this mailbox to verify correct routing
EXPECTED_SPAM_FOLDER_ID=$(fs_query "SELECT id FROM folders WHERE mailbox_id = $MAILBOX_ID AND type = 5 LIMIT 1" 2>/dev/null)

# JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "conversation_found": $CONV_FOUND,
    "conversation_id": "${CONV_ID}",
    "current_status": "${CURRENT_STATUS}",
    "current_folder_id": "${CURRENT_FOLDER_ID}",
    "current_folder_type": "${FOLDER_TYPE}",
    "expected_spam_folder_id": "${EXPECTED_SPAM_FOLDER_ID}",
    "updated_at_unix": ${UPDATED_AT_UNIX},
    "was_updated_during_task": $WAS_UPDATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="