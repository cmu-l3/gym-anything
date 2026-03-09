#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting results for move_conversation_to_mailbox ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read saved IDs from setup
CONV_ID=$(cat /tmp/conversation_id.txt 2>/dev/null || echo "")
GENERAL_MAILBOX_ID=$(cat /tmp/general_mailbox_id.txt 2>/dev/null || echo "")
NETSUPPORT_MAILBOX_ID=$(cat /tmp/netsupport_mailbox_id.txt 2>/dev/null || echo "")
INITIAL_MAILBOX_ID=$(cat /tmp/initial_mailbox_id.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Conversation ID: $CONV_ID"
echo "General Mailbox ID: $GENERAL_MAILBOX_ID"
echo "IT Network Support Mailbox ID: $NETSUPPORT_MAILBOX_ID"
echo "Initial mailbox_id: $INITIAL_MAILBOX_ID"
echo "Task start time: $TASK_START"

# Query current state of the conversation
CURRENT_MAILBOX_ID=""
CURRENT_SUBJECT=""
CURRENT_STATUS=""
CONVERSATION_EXISTS="0"
UPDATED_AT="0"
MOVED_TO_CORRECT="false"
WAS_MODIFIED="false"
REMOVED_FROM_ORIGINAL="false"

if [ -n "$CONV_ID" ]; then
    # Check existence
    CONVERSATION_EXISTS=$(fs_query "SELECT COUNT(*) FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
    
    if [ "$CONVERSATION_EXISTS" = "1" ]; then
        # Get current details
        CURRENT_MAILBOX_ID=$(fs_query "SELECT mailbox_id FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
        # Use simple sed to escape double quotes for JSON safety later
        CURRENT_SUBJECT=$(fs_query "SELECT subject FROM conversations WHERE id = $CONV_ID" 2>/dev/null | sed 's/"/\\"/g')
        CURRENT_STATUS=$(fs_query "SELECT status FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
        # Get timestamp
        UPDATED_AT=$(fs_query "SELECT UNIX_TIMESTAMP(updated_at) FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
        
        # Check if moved to correct mailbox
        if [ -n "$CURRENT_MAILBOX_ID" ] && [ -n "$NETSUPPORT_MAILBOX_ID" ] && [ "$CURRENT_MAILBOX_ID" = "$NETSUPPORT_MAILBOX_ID" ]; then
            MOVED_TO_CORRECT="true"
        fi
        
        # Check if removed from original
        if [ -n "$INITIAL_MAILBOX_ID" ] && [ -n "$CURRENT_MAILBOX_ID" ] && [ "$INITIAL_MAILBOX_ID" != "$CURRENT_MAILBOX_ID" ]; then
            REMOVED_FROM_ORIGINAL="true"
        fi
        
        # Check anti-gaming timestamp
        if [ -n "$UPDATED_AT" ] && [ "$UPDATED_AT" != "0" ] && [ -n "$TASK_START" ] && [ "$TASK_START" != "0" ]; then
            if [ "$UPDATED_AT" -ge "$TASK_START" ]; then
                WAS_MODIFIED="true"
            fi
        fi
    fi
fi

# Convert "1" to "true" for JSON boolean fields where appropriate
if [ "$CONVERSATION_EXISTS" = "1" ]; then
    CONVERSATION_EXISTS_BOOL="true"
else
    CONVERSATION_EXISTS_BOOL="false"
fi

echo "Current mailbox_id: $CURRENT_MAILBOX_ID"
echo "Current subject: $CURRENT_SUBJECT"
echo "Conversation exists: $CONVERSATION_EXISTS_BOOL"
echo "Moved to correct: $MOVED_TO_CORRECT"
echo "Was modified: $WAS_MODIFIED"

# Create JSON result with permission handling
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "conversation_id": "${CONV_ID}",
    "general_mailbox_id": "${GENERAL_MAILBOX_ID}",
    "netsupport_mailbox_id": "${NETSUPPORT_MAILBOX_ID}",
    "initial_mailbox_id": "${INITIAL_MAILBOX_ID}",
    "current_mailbox_id": "${CURRENT_MAILBOX_ID}",
    "current_subject": "${CURRENT_SUBJECT}",
    "conversation_still_exists": ${CONVERSATION_EXISTS_BOOL},
    "moved_to_correct_mailbox": ${MOVED_TO_CORRECT},
    "was_modified": ${WAS_MODIFIED},
    "removed_from_original": ${REMOVED_FROM_ORIGINAL},
    "task_start_time": ${TASK_START},
    "updated_at": "${UPDATED_AT}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Results JSON ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="