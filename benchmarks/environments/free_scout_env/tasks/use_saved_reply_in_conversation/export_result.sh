#!/bin/bash
echo "=== Exporting use_saved_reply_in_conversation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load IDs
CONV_ID=$(cat /tmp/target_conversation_id.txt 2>/dev/null || echo "")
INITIAL_THREAD_COUNT=$(cat /tmp/initial_thread_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$CONV_ID" ]; then
    # Fallback search
    CONV_ID=$(fs_query "SELECT id FROM conversations WHERE subject LIKE '%Projector Maintenance%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

echo "Checking Conversation ID: $CONV_ID"

CURRENT_THREAD_COUNT="0"
NEW_REPLY_FOUND="false"
REPLY_BODY=""
REPLY_AUTHOR_ID=""
REPLY_CREATED_AT=""

if [ -n "$CONV_ID" ]; then
    CURRENT_THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id = $CONV_ID" 2>/dev/null || echo "0")
    
    # Get the latest thread (reply)
    # type=1 (Note?), type=2 (Message/Reply) - usually FreeScout uses 1 for customer, 2 for user reply? 
    # Actually schema: type 1=Message, 2=Note.
    # created_by_user_id IS NOT NULL means it's an agent reply.
    
    LATEST_THREAD=$(fs_query "SELECT id, body, created_by_user_id, created_at FROM threads WHERE conversation_id = $CONV_ID AND created_by_user_id IS NOT NULL ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$LATEST_THREAD" ]; then
        # Check if this thread was created after task start
        # created_at format is usually 'YYYY-MM-DD HH:MM:SS'
        THREAD_DATE=$(echo "$LATEST_THREAD" | cut -f4)
        THREAD_TIMESTAMP=$(date -d "$THREAD_DATE" +%s 2>/dev/null || echo "0")
        
        if [ "$THREAD_TIMESTAMP" -ge "$TASK_START_TIME" ]; then
            NEW_REPLY_FOUND="true"
            REPLY_BODY=$(echo "$LATEST_THREAD" | cut -f2)
            REPLY_AUTHOR_ID=$(echo "$LATEST_THREAD" | cut -f3)
            REPLY_CREATED_AT="$THREAD_DATE"
        else
            echo "Latest thread is old ($THREAD_DATE vs start $TASK_START_TIME)"
        fi
    fi
fi

# Escape body for JSON
ESCAPED_BODY=$(echo "$REPLY_BODY" | jq -R '.')

# Get Admin ID for verification
ADMIN_ID=$(fs_query "SELECT id FROM users WHERE email = 'admin@helpdesk.local' LIMIT 1" 2>/dev/null || echo "1")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "conversation_found": $([ -n "$CONV_ID" ] && echo "true" || echo "false"),
    "initial_thread_count": $INITIAL_THREAD_COUNT,
    "current_thread_count": $CURRENT_THREAD_COUNT,
    "new_reply_found": $NEW_REPLY_FOUND,
    "reply_body": $ESCAPED_BODY,
    "reply_author_id": "${REPLY_AUTHOR_ID}",
    "admin_id": "${ADMIN_ID}",
    "task_start_timestamp": $TASK_START_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="