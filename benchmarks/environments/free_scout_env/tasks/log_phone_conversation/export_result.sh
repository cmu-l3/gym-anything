#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Log Phone Conversation Result ==="

RESULT_FILE="/tmp/task_result.json"

# Load initial state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_CONV_COUNT=$(cat /tmp/initial_conv_count.txt 2>/dev/null || echo "0")
INITIAL_PHONE_COUNT=$(cat /tmp/initial_phone_count.txt 2>/dev/null || echo "0")
EXPECTED_MAILBOX_ID=$(cat /tmp/task_mailbox_id.txt 2>/dev/null || echo "0")
EXPECTED_CUSTOMER_ID=$(cat /tmp/task_customer_id.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get current counts
CURRENT_CONV_COUNT=$(get_conversation_count)
CURRENT_PHONE_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations WHERE type = 2" 2>/dev/null || echo "0")

NEW_CONV_DIFF=$((CURRENT_CONV_COUNT - INITIAL_CONV_COUNT))
NEW_PHONE_DIFF=$((CURRENT_PHONE_COUNT - INITIAL_PHONE_COUNT))

# Find the specific conversation created during the task
# Look for newest conversation created after task start
# We prefer type=2 (Phone), but will grab whatever is newest to diagnose errors
CONV_ID=""
CONV_TYPE=""
CONV_SUBJECT=""
CONV_MAILBOX_ID=""
CONV_CUSTOMER_ID=""
CONV_BODY=""
CONV_CREATED_AT=""

# Query for newest conversation created after start time
# Using timestamp check in SQL is safest
CONV_DATA=$(fs_query "SELECT id, type, subject, mailbox_id, customer_id, created_at FROM conversations WHERE UNIX_TIMESTAMP(created_at) >= $TASK_START ORDER BY id DESC LIMIT 1" 2>/dev/null)

if [ -n "$CONV_DATA" ]; then
    CONV_ID=$(echo "$CONV_DATA" | cut -f1)
    CONV_TYPE=$(echo "$CONV_DATA" | cut -f2)
    CONV_SUBJECT=$(echo "$CONV_DATA" | cut -f3)
    CONV_MAILBOX_ID=$(echo "$CONV_DATA" | cut -f4)
    CONV_CUSTOMER_ID=$(echo "$CONV_DATA" | cut -f5)
    CONV_CREATED_AT=$(echo "$CONV_DATA" | cut -f6)

    # Get the body of the first thread
    if [ -n "$CONV_ID" ]; then
        CONV_BODY=$(fs_query "SELECT body FROM threads WHERE conversation_id = $CONV_ID ORDER BY id ASC LIMIT 1" 2>/dev/null || echo "")
    fi
fi

# Get customer email for verification
ACTUAL_CUSTOMER_EMAIL=""
if [ -n "$CONV_CUSTOMER_ID" ] && [ "$CONV_CUSTOMER_ID" != "NULL" ]; then
    ACTUAL_CUSTOMER_EMAIL=$(fs_query "SELECT email FROM emails WHERE customer_id = $CONV_CUSTOMER_ID LIMIT 1" 2>/dev/null || echo "")
fi

# Get mailbox name for verification
ACTUAL_MAILBOX_NAME=""
if [ -n "$CONV_MAILBOX_ID" ]; then
    ACTUAL_MAILBOX_NAME=$(fs_query "SELECT name FROM mailboxes WHERE id = $CONV_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
fi

# Escape strings for JSON
CONV_SUBJECT_ESC=$(echo "$CONV_SUBJECT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
CONV_BODY_ESC=$(echo "$CONV_BODY" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
ACTUAL_MAILBOX_NAME_ESC=$(echo "$ACTUAL_MAILBOX_NAME" | sed 's/"/\\"/g')

# Write result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_conv_count": $INITIAL_CONV_COUNT,
    "final_conv_count": $CURRENT_CONV_COUNT,
    "initial_phone_count": $INITIAL_PHONE_COUNT,
    "final_phone_count": $CURRENT_PHONE_COUNT,
    "new_conv_diff": $NEW_CONV_DIFF,
    "new_phone_diff": $NEW_PHONE_DIFF,
    "conversation": {
        "id": "${CONV_ID}",
        "type": "${CONV_TYPE}",
        "subject": "${CONV_SUBJECT_ESC}",
        "mailbox_id": "${CONV_MAILBOX_ID}",
        "mailbox_name": "${ACTUAL_MAILBOX_NAME_ESC}",
        "customer_id": "${CONV_CUSTOMER_ID}",
        "customer_email": "${ACTUAL_CUSTOMER_EMAIL}",
        "body": "${CONV_BODY_ESC}",
        "created_at": "${CONV_CREATED_AT}"
    },
    "expected_mailbox_id": "${EXPECTED_MAILBOX_ID}",
    "expected_customer_id": "${EXPECTED_CUSTOMER_ID}"
}
EOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="