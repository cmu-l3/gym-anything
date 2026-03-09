#!/bin/bash
echo "=== Exporting support_backlog_triage result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

MAILBOX_ID=$(cat /tmp/general_mailbox_id 2>/dev/null || echo "")
ADMIN_ID=$(cat /tmp/admin_user_id 2>/dev/null || echo "1")
DEREK_ID=$(cat /tmp/derek_user_id 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
UNRESPONDED_IDS=$(cat /tmp/unresponded_conv_ids 2>/dev/null || echo "")
CLOSED_IDS=$(cat /tmp/closed_conv_ids 2>/dev/null || echo "")

TARGET_SUBJECT="Software installation failure"

# ---- Tag "awaiting-first-response" stats ----
TAG_ID=$(fs_query "SELECT id FROM tags WHERE LOWER(name)='awaiting-first-response' LIMIT 1" 2>/dev/null || echo "")
TAG_EXISTS=false
TAGGED_COUNT=0
TAGGED_ASSIGNED_TO_ADMIN=0
if [ -n "$TAG_ID" ]; then
    TAG_EXISTS=true
    TAGGED_COUNT=$(fs_query "SELECT COUNT(*) FROM conversation_tag ct JOIN conversations c ON ct.conversation_id=c.id WHERE ct.tag_id=$TAG_ID AND c.mailbox_id=$MAILBOX_ID" 2>/dev/null || echo "0")
    if [ -n "$ADMIN_ID" ]; then
        TAGGED_ASSIGNED_TO_ADMIN=$(fs_query "SELECT COUNT(*) FROM conversation_tag ct JOIN conversations c ON ct.conversation_id=c.id WHERE ct.tag_id=$TAG_ID AND c.mailbox_id=$MAILBOX_ID AND c.user_id=$ADMIN_ID" 2>/dev/null || echo "0")
    fi
fi

# ---- Count internal notes on the 4 unresponded conversations ----
NOTES_COUNT=0
if [ -n "$UNRESPONDED_IDS" ]; then
    IFS=',' read -ra CONV_ARR <<< "$UNRESPONDED_IDS"
    for CONV_ID in "${CONV_ARR[@]}"; do
        CONV_ID=$(echo "$CONV_ID" | tr -d ' ')
        if [ -n "$CONV_ID" ] && [ "$CONV_ID" != "" ]; then
            # Notes in FreeScout are threads with type=3
            NOTE_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id=$CONV_ID AND type=3" 2>/dev/null || echo "0")
            if [ "$NOTE_COUNT" != "0" ]; then
                NOTES_COUNT=$((NOTES_COUNT + 1))
            fi
        fi
    done
fi

# ---- Count reopened conversations (closed → active) ----
REOPENED_COUNT=0
if [ -n "$CLOSED_IDS" ]; then
    IFS=',' read -ra CLOSED_ARR <<< "$CLOSED_IDS"
    for CONV_ID in "${CLOSED_ARR[@]}"; do
        CONV_ID=$(echo "$CONV_ID" | tr -d ' ')
        if [ -n "$CONV_ID" ] && [ "$CONV_ID" != "" ]; then
            STATUS=$(fs_query "SELECT status FROM conversations WHERE id=$CONV_ID LIMIT 1" 2>/dev/null || echo "3")
            if [ "$STATUS" = "1" ] || [ "$STATUS" = "2" ]; then
                REOPENED_COUNT=$((REOPENED_COUNT + 1))
            fi
        fi
    done
fi

# ---- Check target conversation: Software installation failure ----
TARGET_CONV_ID=$(fs_query "SELECT id FROM conversations WHERE LOWER(subject) LIKE '%software installation failure%' AND mailbox_id=$MAILBOX_ID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
TARGET_REPLIED=false
TARGET_REPLY_BODY=""
TARGET_ASSIGNED_TO_DEREK=false

if [ -n "$TARGET_CONV_ID" ]; then
    # Check for agent reply
    AGENT_REPLY=$(fs_query "SELECT body FROM threads WHERE conversation_id=$TARGET_CONV_ID AND type=2 ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$AGENT_REPLY" ]; then
        TARGET_REPLIED=true
        TARGET_REPLY_BODY=$(echo "$AGENT_REPLY" | head -c 500)
    fi

    # Check if assigned to Derek
    TARGET_USER_ID=$(fs_query "SELECT user_id FROM conversations WHERE id=$TARGET_CONV_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$DEREK_ID" ] && [ "$TARGET_USER_ID" = "$DEREK_ID" ]; then
        TARGET_ASSIGNED_TO_DEREK=true
    fi
fi

# Escape for JSON
TARGET_REPLY_BODY=$(echo "$TARGET_REPLY_BODY" | sed 's/"/\\"/g' | tr '\n' ' ')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": ${TASK_START},
    "tag_exists": ${TAG_EXISTS},
    "tagged_count": ${TAGGED_COUNT},
    "tagged_assigned_to_admin": ${TAGGED_ASSIGNED_TO_ADMIN},
    "notes_on_unresponded": ${NOTES_COUNT},
    "reopened_count": ${REOPENED_COUNT},
    "target_conv_id": "${TARGET_CONV_ID}",
    "target_replied": ${TARGET_REPLIED},
    "target_reply_body": "${TARGET_REPLY_BODY}",
    "target_assigned_to_derek": ${TARGET_ASSIGNED_TO_DEREK},
    "derek_id": "${DEREK_ID}",
    "admin_id": "${ADMIN_ID}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
