#!/bin/bash
echo "=== Exporting assign_conversation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

CONV_ID=$(cat /tmp/conversation_id 2>/dev/null || echo "")
EXPECTED_SUBJECT="Payment issue"

# Find the conversation
if [ -z "$CONV_ID" ]; then
    CONV_ID=$(fs_query "SELECT id FROM conversations WHERE subject = '$EXPECTED_SUBJECT' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
fi

CONV_FOUND="false"
CONV_SUBJECT=""
CONV_USER_ID=""
ASSIGNEE_FIRST=""
ASSIGNEE_LAST=""
ASSIGNEE_EMAIL=""

if [ -n "$CONV_ID" ]; then
    CONV_DATA=$(fs_query "SELECT id, subject, user_id FROM conversations WHERE id = $CONV_ID LIMIT 1" 2>/dev/null)
    if [ -n "$CONV_DATA" ]; then
        CONV_FOUND="true"
        CONV_SUBJECT=$(echo "$CONV_DATA" | cut -f2)
        CONV_USER_ID=$(echo "$CONV_DATA" | cut -f3)

        # Get assignee details if assigned
        if [ -n "$CONV_USER_ID" ] && [ "$CONV_USER_ID" != "NULL" ] && [ "$CONV_USER_ID" != "" ]; then
            ASSIGNEE_DATA=$(fs_query "SELECT first_name, last_name, email FROM users WHERE id = $CONV_USER_ID LIMIT 1" 2>/dev/null)
            if [ -n "$ASSIGNEE_DATA" ]; then
                ASSIGNEE_FIRST=$(echo "$ASSIGNEE_DATA" | cut -f1)
                ASSIGNEE_LAST=$(echo "$ASSIGNEE_DATA" | cut -f2)
                ASSIGNEE_EMAIL=$(echo "$ASSIGNEE_DATA" | cut -f3)
            fi
        fi
    fi
fi

IS_ASSIGNED="false"
if [ -n "$CONV_USER_ID" ] && [ "$CONV_USER_ID" != "NULL" ] && [ "$CONV_USER_ID" != "" ]; then
    IS_ASSIGNED="true"
fi

# Escape for JSON
CONV_SUBJECT=$(echo "$CONV_SUBJECT" | sed 's/"/\\"/g')
ASSIGNEE_FIRST=$(echo "$ASSIGNEE_FIRST" | sed 's/"/\\"/g')
ASSIGNEE_LAST=$(echo "$ASSIGNEE_LAST" | sed 's/"/\\"/g')
ASSIGNEE_EMAIL=$(echo "$ASSIGNEE_EMAIL" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "conversation_found": ${CONV_FOUND},
    "conversation_id": "${CONV_ID}",
    "conversation_subject": "${CONV_SUBJECT}",
    "is_assigned": ${IS_ASSIGNED},
    "assignee_user_id": "${CONV_USER_ID}",
    "assignee_first_name": "${ASSIGNEE_FIRST}",
    "assignee_last_name": "${ASSIGNEE_LAST}",
    "assignee_email": "${ASSIGNEE_EMAIL}",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
