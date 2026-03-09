#!/bin/bash
echo "=== Exporting create_conversation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

INITIAL_COUNT=$(cat /tmp/initial_conversation_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_conversation_count)

EXPECTED_SUBJECT="Peripheral compatibility"
EXPECTED_EMAIL="clarkeashley@example.com"

# Search for conversation by subject
CONV_DATA=$(find_conversation_by_subject "$EXPECTED_SUBJECT")
CONV_FOUND="false"
CONV_ID=""
CONV_NUMBER=""
CONV_SUBJECT=""
CONV_STATUS=""
CONV_MAILBOX_ID=""
CONV_USER_ID=""
CONV_CUSTOMER_ID=""

if [ -n "$CONV_DATA" ]; then
    CONV_FOUND="true"
    CONV_ID=$(echo "$CONV_DATA" | cut -f1)
    CONV_NUMBER=$(echo "$CONV_DATA" | cut -f2)
    CONV_SUBJECT=$(echo "$CONV_DATA" | cut -f3)
    CONV_STATUS=$(echo "$CONV_DATA" | cut -f4)
    CONV_MAILBOX_ID=$(echo "$CONV_DATA" | cut -f5)
    CONV_USER_ID=$(echo "$CONV_DATA" | cut -f6)
    CONV_CUSTOMER_ID=$(echo "$CONV_DATA" | cut -f7)
fi

# If not found by subject, try newest conversation
if [ "$CONV_FOUND" = "false" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    CONV_DATA=$(fs_query "SELECT id, number, subject, status, mailbox_id, user_id, customer_id FROM conversations ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$CONV_DATA" ]; then
        CONV_FOUND="true"
        CONV_ID=$(echo "$CONV_DATA" | cut -f1)
        CONV_NUMBER=$(echo "$CONV_DATA" | cut -f2)
        CONV_SUBJECT=$(echo "$CONV_DATA" | cut -f3)
        CONV_STATUS=$(echo "$CONV_DATA" | cut -f4)
        CONV_MAILBOX_ID=$(echo "$CONV_DATA" | cut -f5)
        CONV_USER_ID=$(echo "$CONV_DATA" | cut -f6)
        CONV_CUSTOMER_ID=$(echo "$CONV_DATA" | cut -f7)
    fi
fi

# Check if threads exist for this conversation (message body was written)
THREAD_COUNT="0"
if [ -n "$CONV_ID" ]; then
    THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id = $CONV_ID" 2>/dev/null || echo "0")
fi

# Check customer email association
CUSTOMER_EMAIL=""
if [ -n "$CONV_CUSTOMER_ID" ] && [ "$CONV_CUSTOMER_ID" != "NULL" ] && [ "$CONV_CUSTOMER_ID" != "0" ]; then
    CUSTOMER_EMAIL=$(fs_query "SELECT e.email FROM emails e WHERE e.customer_id = $CONV_CUSTOMER_ID LIMIT 1" 2>/dev/null || echo "")
fi

# Escape for JSON
CONV_SUBJECT=$(echo "$CONV_SUBJECT" | sed 's/"/\\"/g')
CUSTOMER_EMAIL=$(echo "$CUSTOMER_EMAIL" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT},
    "current_count": ${CURRENT_COUNT},
    "conversation_found": ${CONV_FOUND},
    "conversation_id": "${CONV_ID}",
    "conversation_number": "${CONV_NUMBER}",
    "conversation_subject": "${CONV_SUBJECT}",
    "conversation_status": "${CONV_STATUS}",
    "conversation_mailbox_id": "${CONV_MAILBOX_ID}",
    "thread_count": ${THREAD_COUNT},
    "customer_email": "${CUSTOMER_EMAIL}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
