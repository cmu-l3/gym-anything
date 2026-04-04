#!/bin/bash
echo "=== Exporting Add Internal Follower Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Load IDs
CONV_ID=$(cat /tmp/task_conv_id.txt 2>/dev/null || echo "")
SARAH_ID=$(cat /tmp/task_sarah_id.txt 2>/dev/null || echo "")
MARCUS_ID=$(cat /tmp/task_marcus_id.txt 2>/dev/null || echo "")

if [ -z "$CONV_ID" ]; then
    echo "ERROR: Conversation ID not found"
    # Try to find it dynamically as fallback
    CONV_DATA=$(find_conversation_by_subject "Potential Data Exfiltration detected on server DB-01")
    if [ -n "$CONV_DATA" ]; then
        CONV_ID=$(echo "$CONV_DATA" | cut -f1)
    fi
fi

echo "Checking state for Conversation $CONV_ID..."

# 1. Check if Marcus is following (entry in conversation_user table)
# conversation_user table links conversations and users for following
IS_FOLLOWER="false"
if [ -n "$CONV_ID" ] && [ -n "$MARCUS_ID" ]; then
    FOLLOWER_COUNT=$(fs_query "SELECT COUNT(*) FROM conversation_user WHERE conversation_id=$CONV_ID AND user_id=$MARCUS_ID" 2>/dev/null || echo "0")
    if [ "$FOLLOWER_COUNT" -gt 0 ]; then
        IS_FOLLOWER="true"
    fi
fi

# 2. Check current Assignee
CURRENT_ASSIGNEE_ID=""
CURRENT_STATUS=""
if [ -n "$CONV_ID" ]; then
    CONV_INFO=$(fs_query "SELECT user_id, status FROM conversations WHERE id=$CONV_ID" 2>/dev/null)
    CURRENT_ASSIGNEE_ID=$(echo "$CONV_INFO" | cut -f1)
    CURRENT_STATUS=$(echo "$CONV_INFO" | cut -f2)
fi

# 3. Verify Sarah is still assignee
ASSIGNEE_IS_SARAH="false"
if [ "$CURRENT_ASSIGNEE_ID" = "$SARAH_ID" ]; then
    ASSIGNEE_IS_SARAH="true"
fi

# 4. Check if accidentally assigned to Marcus
ASSIGNEE_IS_MARCUS="false"
if [ "$CURRENT_ASSIGNEE_ID" = "$MARCUS_ID" ]; then
    ASSIGNEE_IS_MARCUS="true"
fi

# 5. Check Ticket Active (Status 1)
IS_ACTIVE="false"
if [ "$CURRENT_STATUS" = "1" ]; then
    IS_ACTIVE="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "conversation_id": "${CONV_ID}",
    "marcus_is_follower": ${IS_FOLLOWER},
    "assignee_is_sarah": ${ASSIGNEE_IS_SARAH},
    "assignee_is_marcus": ${ASSIGNEE_IS_MARCUS},
    "ticket_is_active": ${IS_ACTIVE},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="