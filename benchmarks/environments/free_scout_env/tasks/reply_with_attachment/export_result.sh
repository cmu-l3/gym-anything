#!/bin/bash
echo "=== Exporting reply_with_attachment result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Get stored context
CONV_ID=$(cat /tmp/target_conversation_id.txt 2>/dev/null || echo "")
INITIAL_THREAD_COUNT=$(cat /tmp/initial_thread_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$CONV_ID" ]; then
    # Fallback: try to find it by subject if ID file is missing
    CONV_DATA=$(find_conversation_by_subject "Need VPN instructions")
    CONV_ID=$(echo "$CONV_DATA" | cut -f1)
fi

echo "Checking Conversation ID: $CONV_ID"

# 3. Query current state
CURRENT_THREAD_COUNT="0"
REPLY_FOUND="false"
REPLY_ID=""
REPLY_BODY=""
ATTACHMENT_FOUND="false"
ATTACHMENT_NAME=""
ATTACHMENT_SIZE="0"

if [ -n "$CONV_ID" ]; then
    CURRENT_THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id = $CONV_ID" 2>/dev/null || echo "0")
    
    # Find the latest thread of type 'message' (3) or 'forward' (4) created by a user
    # We want the one with the highest ID
    LATEST_REPLY_DATA=$(fs_query "SELECT id, body, created_at FROM threads WHERE conversation_id = $CONV_ID AND type IN (3, 4) ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$LATEST_REPLY_DATA" ]; then
        REPLY_ID=$(echo "$LATEST_REPLY_DATA" | cut -f1)
        # Body might contain tabs/newlines, so we fetch it separately to be safe or just take the snippet
        REPLY_BODY_SNIPPET=$(echo "$LATEST_REPLY_DATA" | cut -f2 | head -c 100)
        
        # Check if this thread has an attachment
        ATTACH_DATA=$(fs_query "SELECT file_name, file_size FROM attachments WHERE thread_id = $REPLY_ID LIMIT 1" 2>/dev/null)
        
        if [ -n "$ATTACH_DATA" ]; then
            ATTACHMENT_FOUND="true"
            ATTACHMENT_NAME=$(echo "$ATTACH_DATA" | cut -f1)
            ATTACHMENT_SIZE=$(echo "$ATTACH_DATA" | cut -f2)
        fi
        
        # Mark reply found if it exists and looks like it was created recently
        # (Since we are checking the LATEST thread, and thread count increased, it's likely the agent's)
        if [ "$CURRENT_THREAD_COUNT" -gt "$INITIAL_THREAD_COUNT" ]; then
            REPLY_FOUND="true"
            # Fetch full body properly to check for content
            REPLY_BODY=$(fs_query "SELECT body FROM threads WHERE id = $REPLY_ID" 2>/dev/null)
        fi
    fi
fi

# 4. JSON Export
# Sanitize strings for JSON
SAFE_ATTACHMENT_NAME=$(echo "$ATTACHMENT_NAME" | sed 's/"/\\"/g')
SAFE_REPLY_BODY=$(echo "$REPLY_BODY" | sed 's/"/\\"/g' | tr -d '\n' | cut -c 1-200)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "conversation_id": "${CONV_ID}",
    "initial_thread_count": ${INITIAL_THREAD_COUNT},
    "current_thread_count": ${CURRENT_THREAD_COUNT},
    "reply_found": ${REPLY_FOUND},
    "reply_id": "${REPLY_ID}",
    "reply_body_preview": "${SAFE_REPLY_BODY}",
    "attachment_found": ${ATTACHMENT_FOUND},
    "attachment_name": "${SAFE_ATTACHMENT_NAME}",
    "attachment_size": ${ATTACHMENT_SIZE},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="