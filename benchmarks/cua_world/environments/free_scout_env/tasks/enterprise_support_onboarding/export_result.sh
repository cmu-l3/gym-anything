#!/bin/bash
echo "=== Exporting enterprise_support_onboarding result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

TECH_MAILBOX_ID=$(cat /tmp/tech_mailbox_id 2>/dev/null || echo "")
BILLING_MAILBOX_ID=$(cat /tmp/billing_mailbox_id 2>/dev/null || echo "")
INITIAL_MAILBOX_COUNT=$(cat /tmp/initial_mailbox_count 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count 2>/dev/null || echo "0")
INITIAL_SAVED_REPLY_COUNT=$(cat /tmp/initial_saved_reply_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ---- Check Enterprise Support mailbox ----
ENTERPRISE_MAILBOX_DATA=$(fs_query "SELECT id, name, email FROM mailboxes WHERE LOWER(email)='enterprise@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
ENTERPRISE_MAILBOX_FOUND=false
ENTERPRISE_MAILBOX_ID=""
ENTERPRISE_MAILBOX_NAME=""
if [ -n "$ENTERPRISE_MAILBOX_DATA" ]; then
    ENTERPRISE_MAILBOX_FOUND=true
    ENTERPRISE_MAILBOX_ID=$(echo "$ENTERPRISE_MAILBOX_DATA" | cut -f1)
    ENTERPRISE_MAILBOX_NAME=$(echo "$ENTERPRISE_MAILBOX_DATA" | cut -f2)
fi

# ---- Check James Kowalski ----
JAMES_DATA=$(fs_query "SELECT id, first_name, last_name, email, role FROM users WHERE LOWER(email)='james.kowalski@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
JAMES_FOUND=false
JAMES_ID=""
JAMES_ROLE=0
if [ -n "$JAMES_DATA" ]; then
    JAMES_FOUND=true
    JAMES_ID=$(echo "$JAMES_DATA" | cut -f1)
    JAMES_ROLE=$(echo "$JAMES_DATA" | cut -f5)
fi

# ---- Check Priya Sharma ----
PRIYA_DATA=$(fs_query "SELECT id, first_name, last_name, email, role FROM users WHERE LOWER(email)='priya.sharma@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
PRIYA_FOUND=false
PRIYA_ID=""
PRIYA_ROLE=0
if [ -n "$PRIYA_DATA" ]; then
    PRIYA_FOUND=true
    PRIYA_ID=$(echo "$PRIYA_DATA" | cut -f1)
    PRIYA_ROLE=$(echo "$PRIYA_DATA" | cut -f5)
fi

# ---- Check James mailbox access (needs both Technical + Enterprise) ----
JAMES_TECH_ACCESS=false
JAMES_ENTERPRISE_ACCESS=false
if [ -n "$JAMES_ID" ] && [ -n "$TECH_MAILBOX_ID" ]; then
    CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$JAMES_ID AND mailbox_id=$TECH_MAILBOX_ID" 2>/dev/null || echo "0")
    [ "$CNT" != "0" ] && JAMES_TECH_ACCESS=true
fi
if [ -n "$JAMES_ID" ] && [ -n "$ENTERPRISE_MAILBOX_ID" ]; then
    CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$JAMES_ID AND mailbox_id=$ENTERPRISE_MAILBOX_ID" 2>/dev/null || echo "0")
    [ "$CNT" != "0" ] && JAMES_ENTERPRISE_ACCESS=true
fi

# ---- Check Priya mailbox access (Enterprise only) ----
PRIYA_ENTERPRISE_ACCESS=false
if [ -n "$PRIYA_ID" ] && [ -n "$ENTERPRISE_MAILBOX_ID" ]; then
    CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$PRIYA_ID AND mailbox_id=$ENTERPRISE_MAILBOX_ID" 2>/dev/null || echo "0")
    [ "$CNT" != "0" ] && PRIYA_ENTERPRISE_ACCESS=true
fi

# ---- Check saved reply "Enterprise Acknowledgment" ----
SAVED_REPLY_DATA=$(fs_query "SELECT id, name FROM saved_replies WHERE LOWER(name) LIKE '%enterprise%' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
SAVED_REPLY_FOUND=false
SAVED_REPLY_NAME=""
SAVED_REPLY_TEXT=""
if [ -n "$SAVED_REPLY_DATA" ]; then
    SAVED_REPLY_FOUND=true
    SR_ID=$(echo "$SAVED_REPLY_DATA" | cut -f1)
    SAVED_REPLY_NAME=$(echo "$SAVED_REPLY_DATA" | cut -f2)
    SAVED_REPLY_TEXT=$(fs_query "SELECT text FROM saved_replies WHERE id=$SR_ID LIMIT 1" 2>/dev/null || echo "")
fi

# ---- Check tag "technical" on Technical Support conversations ----
TECH_TAGGED_COUNT=0
TAG_TECH_ID=$(fs_query "SELECT id FROM tags WHERE LOWER(name)='technical' LIMIT 1" 2>/dev/null || echo "")
if [ -n "$TAG_TECH_ID" ] && [ -n "$TECH_MAILBOX_ID" ]; then
    TECH_TAGGED_COUNT=$(fs_query "SELECT COUNT(*) FROM conversation_tag ct JOIN conversations c ON ct.conversation_id=c.id WHERE ct.tag_id=$TAG_TECH_ID AND c.mailbox_id=$TECH_MAILBOX_ID" 2>/dev/null || echo "0")
fi

# ---- Check Billing conversations assigned to Sarah Mitchell ----
SARAH_ID=$(fs_query "SELECT id FROM users WHERE LOWER(email)='sarah.mitchell@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
BILLING_ASSIGNED_TO_SARAH=0
if [ -n "$SARAH_ID" ] && [ -n "$BILLING_MAILBOX_ID" ]; then
    BILLING_ASSIGNED_TO_SARAH=$(fs_query "SELECT COUNT(*) FROM conversations WHERE mailbox_id=$BILLING_MAILBOX_ID AND user_id=$SARAH_ID" 2>/dev/null || echo "0")
fi

CURRENT_MAILBOX_COUNT=$(fs_query "SELECT COUNT(*) FROM mailboxes" 2>/dev/null || echo "0")
CURRENT_USER_COUNT=$(fs_query "SELECT COUNT(*) FROM users" 2>/dev/null || echo "0")

# Escape strings for JSON
ENTERPRISE_MAILBOX_NAME=$(echo "$ENTERPRISE_MAILBOX_NAME" | sed 's/"/\\"/g')
SAVED_REPLY_NAME=$(echo "$SAVED_REPLY_NAME" | sed 's/"/\\"/g')
SAVED_REPLY_TEXT=$(echo "$SAVED_REPLY_TEXT" | head -c 500 | sed 's/"/\\"/g' | tr '\n' ' ')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": ${TASK_START},
    "initial_mailbox_count": ${INITIAL_MAILBOX_COUNT},
    "current_mailbox_count": ${CURRENT_MAILBOX_COUNT},
    "initial_user_count": ${INITIAL_USER_COUNT},
    "current_user_count": ${CURRENT_USER_COUNT},
    "initial_saved_reply_count": ${INITIAL_SAVED_REPLY_COUNT},
    "enterprise_mailbox_found": ${ENTERPRISE_MAILBOX_FOUND},
    "enterprise_mailbox_id": "${ENTERPRISE_MAILBOX_ID}",
    "enterprise_mailbox_name": "${ENTERPRISE_MAILBOX_NAME}",
    "james_found": ${JAMES_FOUND},
    "james_id": "${JAMES_ID}",
    "james_role": ${JAMES_ROLE:-0},
    "james_tech_access": ${JAMES_TECH_ACCESS},
    "james_enterprise_access": ${JAMES_ENTERPRISE_ACCESS},
    "priya_found": ${PRIYA_FOUND},
    "priya_id": "${PRIYA_ID}",
    "priya_role": ${PRIYA_ROLE:-0},
    "priya_enterprise_access": ${PRIYA_ENTERPRISE_ACCESS},
    "saved_reply_found": ${SAVED_REPLY_FOUND},
    "saved_reply_name": "${SAVED_REPLY_NAME}",
    "saved_reply_text_preview": "${SAVED_REPLY_TEXT}",
    "tech_tagged_count": ${TECH_TAGGED_COUNT},
    "billing_assigned_to_sarah": ${BILLING_ASSIGNED_TO_SARAH},
    "sarah_id": "${SARAH_ID}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
