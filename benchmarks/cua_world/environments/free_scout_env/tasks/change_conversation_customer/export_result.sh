#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting change_conversation_customer result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load saved IDs
CONV_ID=$(cat /tmp/conversation_id.txt 2>/dev/null)
WRONG_CUSTOMER_ID=$(cat /tmp/wrong_customer_id.txt 2>/dev/null)
CORRECT_CUSTOMER_ID=$(cat /tmp/correct_customer_id.txt 2>/dev/null)
INITIAL_CUSTOMER_ID=$(cat /tmp/initial_customer_id.txt 2>/dev/null)
MAILBOX_ID=$(cat /tmp/mailbox_id.txt 2>/dev/null)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch current conversation state
if [ -n "$CONV_ID" ]; then
    CURRENT_STATE=$(fs_query "SELECT customer_id, customer_email, subject, mailbox_id, UNIX_TIMESTAMP(updated_at) FROM conversations WHERE id = $CONV_ID" 2>/dev/null)
    
    # Parse results (tab separated)
    CURRENT_CUSTOMER_ID=$(echo "$CURRENT_STATE" | cut -f1)
    CURRENT_CUSTOMER_EMAIL=$(echo "$CURRENT_STATE" | cut -f2)
    CURRENT_SUBJECT=$(echo "$CURRENT_STATE" | cut -f3)
    CURRENT_MAILBOX_ID=$(echo "$CURRENT_STATE" | cut -f4)
    CURRENT_UPDATED_AT=$(echo "$CURRENT_STATE" | cut -f5)
    
    CONV_EXISTS="true"
else
    CONV_EXISTS="false"
fi

# Determine conversation integrity
INTEGRITY="false"
if [ "$CURRENT_SUBJECT" = "Unauthorized Access Attempt - Building C Server Room" ] && \
   [ "$CURRENT_MAILBOX_ID" = "$MAILBOX_ID" ]; then
    INTEGRITY="true"
fi

# Escape strings for JSON
CURRENT_SUBJECT_ESC=$(echo "$CURRENT_SUBJECT" | sed 's/"/\\"/g')
CURRENT_EMAIL_ESC=$(echo "$CURRENT_CUSTOMER_EMAIL" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "conversation_exists": $CONV_EXISTS,
    "conversation_id": "${CONV_ID}",
    "initial_customer_id": "${INITIAL_CUSTOMER_ID}",
    "wrong_customer_id": "${WRONG_CUSTOMER_ID}",
    "correct_customer_id": "${CORRECT_CUSTOMER_ID}",
    "current_customer_id": "${CURRENT_CUSTOMER_ID}",
    "current_customer_email": "${CURRENT_EMAIL_ESC}",
    "integrity_maintained": $INTEGRITY,
    "task_start_time": $TASK_START,
    "last_updated_time": ${CURRENT_UPDATED_AT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="