#!/bin/bash
echo "=== Exporting support_operations_cleanup result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Load stored IDs
CS_MAILBOX_ID=$(cat /tmp/cs_mailbox_id_soc 2>/dev/null || echo "")
TECH_MAILBOX_ID=$(cat /tmp/tech_mailbox_id_soc 2>/dev/null || echo "")
SALES_MAILBOX_ID=$(cat /tmp/sales_mailbox_id_soc 2>/dev/null || echo "")
RAJ_ID=$(cat /tmp/raj_user_id 2>/dev/null || echo "")
NINA_ID=$(cat /tmp/nina_user_id 2>/dev/null || echo "")
BEN_ID=$(cat /tmp/ben_user_id 2>/dev/null || echo "")
TECH_CONV_1=$(cat /tmp/tech_conv_1_id 2>/dev/null || echo "")
TECH_CONV_2=$(cat /tmp/tech_conv_2_id 2>/dev/null || echo "")
TECH_CONV_3=$(cat /tmp/tech_conv_3_id 2>/dev/null || echo "")
TECH_CONV_4=$(cat /tmp/tech_conv_4_id 2>/dev/null || echo "")
CS_CONV_1=$(cat /tmp/cs_conv_1_id 2>/dev/null || echo "")
CS_CONV_2=$(cat /tmp/cs_conv_2_id 2>/dev/null || echo "")
SALES_CONV_1=$(cat /tmp/sales_conv_1_id 2>/dev/null || echo "")
SALES_CONV_2=$(cat /tmp/sales_conv_2_id 2>/dev/null || echo "")
SALES_CONV_3=$(cat /tmp/sales_conv_3_id 2>/dev/null || echo "")
SALES_CONV_4=$(cat /tmp/sales_conv_4_id 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ---- Check misrouted Tech conversations moved to Sales ----
TECH_CONV_3_MAILBOX=""
TECH_CONV_4_MAILBOX=""
TECH_3_IN_SALES=false
TECH_4_IN_SALES=false

if [ -n "$TECH_CONV_3" ]; then
    TECH_CONV_3_MAILBOX=$(fs_query "SELECT mailbox_id FROM conversations WHERE id=$TECH_CONV_3 LIMIT 1" 2>/dev/null || echo "")
    [ "$TECH_CONV_3_MAILBOX" = "$SALES_MAILBOX_ID" ] && TECH_3_IN_SALES=true
fi
if [ -n "$TECH_CONV_4" ]; then
    TECH_CONV_4_MAILBOX=$(fs_query "SELECT mailbox_id FROM conversations WHERE id=$TECH_CONV_4 LIMIT 1" 2>/dev/null || echo "")
    [ "$TECH_CONV_4_MAILBOX" = "$SALES_MAILBOX_ID" ] && TECH_4_IN_SALES=true
fi
echo "Tech3 moved to Sales: $TECH_3_IN_SALES (mailbox: $TECH_CONV_3_MAILBOX, expected: $SALES_MAILBOX_ID)"
echo "Tech4 moved to Sales: $TECH_4_IN_SALES (mailbox: $TECH_CONV_4_MAILBOX)"

# ---- Check misrouted Sales conversation moved to CS ----
SALES_CONV_3_MAILBOX=""
SALES_3_IN_CS=false
if [ -n "$SALES_CONV_3" ]; then
    SALES_CONV_3_MAILBOX=$(fs_query "SELECT mailbox_id FROM conversations WHERE id=$SALES_CONV_3 LIMIT 1" 2>/dev/null || echo "")
    [ "$SALES_CONV_3_MAILBOX" = "$CS_MAILBOX_ID" ] && SALES_3_IN_CS=true
fi
echo "Sales3 moved to CS: $SALES_3_IN_CS (mailbox: $SALES_CONV_3_MAILBOX, expected: $CS_MAILBOX_ID)"

# ---- Check Raj Patel's permissions ----
RAJ_TECH_ACCESS=false
RAJ_SALES_ACCESS=false
if [ -n "$RAJ_ID" ]; then
    if [ -n "$TECH_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$RAJ_ID AND mailbox_id=$TECH_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && RAJ_TECH_ACCESS=true
    fi
    if [ -n "$SALES_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$RAJ_ID AND mailbox_id=$SALES_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && RAJ_SALES_ACCESS=true
    fi
fi
echo "Raj tech: $RAJ_TECH_ACCESS, sales: $RAJ_SALES_ACCESS (sales should be false)"

# ---- Check Ben Harris's permissions ----
BEN_SALES_ACCESS=false
BEN_CS_ACCESS=false
if [ -n "$BEN_ID" ]; then
    if [ -n "$SALES_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$BEN_ID AND mailbox_id=$SALES_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && BEN_SALES_ACCESS=true
    fi
    if [ -n "$CS_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$BEN_ID AND mailbox_id=$CS_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && BEN_CS_ACCESS=true
    fi
fi
echo "Ben sales: $BEN_SALES_ACCESS, CS: $BEN_CS_ACCESS (CS should be true)"

# ---- Check Tech conv 1 & 2 assigned to Raj ----
TECH_1_USER=""
TECH_2_USER=""
TECH_1_ASSIGNED_RAJ=false
TECH_2_ASSIGNED_RAJ=false
if [ -n "$TECH_CONV_1" ]; then
    TECH_1_USER=$(fs_query "SELECT IFNULL(user_id, 0) FROM conversations WHERE id=$TECH_CONV_1 LIMIT 1" 2>/dev/null || echo "0")
    [ -n "$RAJ_ID" ] && [ "$TECH_1_USER" = "$RAJ_ID" ] && TECH_1_ASSIGNED_RAJ=true
fi
if [ -n "$TECH_CONV_2" ]; then
    TECH_2_USER=$(fs_query "SELECT IFNULL(user_id, 0) FROM conversations WHERE id=$TECH_CONV_2 LIMIT 1" 2>/dev/null || echo "0")
    [ -n "$RAJ_ID" ] && [ "$TECH_2_USER" = "$RAJ_ID" ] && TECH_2_ASSIGNED_RAJ=true
fi
echo "Tech1 assigned to Raj: $TECH_1_ASSIGNED_RAJ, Tech2 assigned to Raj: $TECH_2_ASSIGNED_RAJ"

# ---- Check CS conv 1 & 2 assigned to Nina ----
CS_1_USER=""
CS_2_USER=""
CS_1_ASSIGNED_NINA=false
CS_2_ASSIGNED_NINA=false
if [ -n "$CS_CONV_1" ]; then
    CS_1_USER=$(fs_query "SELECT IFNULL(user_id, 0) FROM conversations WHERE id=$CS_CONV_1 LIMIT 1" 2>/dev/null || echo "0")
    [ -n "$NINA_ID" ] && [ "$CS_1_USER" = "$NINA_ID" ] && CS_1_ASSIGNED_NINA=true
fi
if [ -n "$CS_CONV_2" ]; then
    CS_2_USER=$(fs_query "SELECT IFNULL(user_id, 0) FROM conversations WHERE id=$CS_CONV_2 LIMIT 1" 2>/dev/null || echo "0")
    [ -n "$NINA_ID" ] && [ "$CS_2_USER" = "$NINA_ID" ] && CS_2_ASSIGNED_NINA=true
fi
echo "CS1 assigned to Nina: $CS_1_ASSIGNED_NINA, CS2 assigned to Nina: $CS_2_ASSIGNED_NINA"

# ---- Check saved reply "Sales Inquiry Acknowledgment" ----
SAVED_REPLY_DATA=$(fs_query "SELECT id, name FROM saved_replies WHERE LOWER(name) LIKE '%sales%' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
SAVED_REPLY_FOUND=false
SAVED_REPLY_NAME=""
SAVED_REPLY_TEXT=""
if [ -n "$SAVED_REPLY_DATA" ]; then
    SAVED_REPLY_FOUND=true
    SR_ID=$(echo "$SAVED_REPLY_DATA" | cut -f1)
    SAVED_REPLY_NAME=$(echo "$SAVED_REPLY_DATA" | cut -f2)
    SAVED_REPLY_TEXT=$(fs_query "SELECT text FROM saved_replies WHERE id=$SR_ID LIMIT 1" 2>/dev/null || echo "")
fi
echo "Saved reply found: $SAVED_REPLY_FOUND (name: $SAVED_REPLY_NAME)"

# ---- Count Sales conversations tagged 'needs-follow-up' ----
NFU_TAG_ID=$(fs_query "SELECT id FROM tags WHERE LOWER(name)='needs-follow-up' LIMIT 1" 2>/dev/null || echo "")
TAGGED_SALES_COUNT=0
NFU_TAG_FOUND=false
if [ -n "$NFU_TAG_ID" ]; then
    NFU_TAG_FOUND=true
    if [ -n "$SALES_MAILBOX_ID" ]; then
        TAGGED_SALES_COUNT=$(fs_query "SELECT COUNT(*) FROM conversation_tag ct JOIN conversations c ON ct.conversation_id=c.id WHERE ct.tag_id=$NFU_TAG_ID AND c.mailbox_id=$SALES_MAILBOX_ID" 2>/dev/null || echo "0")
    fi
fi
echo "needs-follow-up tag found: $NFU_TAG_FOUND, tagged Sales count: $TAGGED_SALES_COUNT"

# ---- Count unresponded Sales conversations currently in Sales mailbox ----
SALES_UNRESPONDED_COUNT=0
if [ -n "$SALES_MAILBOX_ID" ]; then
    # Conversations in Sales mailbox with no type=2 (agent) threads
    SALES_UNRESPONDED_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations c WHERE c.mailbox_id=$SALES_MAILBOX_ID AND NOT EXISTS (SELECT 1 FROM threads t WHERE t.conversation_id=c.id AND t.type=2)" 2>/dev/null || echo "0")
fi
echo "Unresponded conversations in Sales: $SALES_UNRESPONDED_COUNT"

# Escape strings
SAVED_REPLY_NAME=$(echo "$SAVED_REPLY_NAME" | sed 's/"/\\"/g')
SAVED_REPLY_TEXT=$(echo "$SAVED_REPLY_TEXT" | head -c 500 | sed 's/"/\\"/g' | tr '\n' ' ')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": ${TASK_START},
    "cs_mailbox_id": "${CS_MAILBOX_ID}",
    "tech_mailbox_id": "${TECH_MAILBOX_ID}",
    "sales_mailbox_id": "${SALES_MAILBOX_ID}",
    "raj_id": "${RAJ_ID}",
    "nina_id": "${NINA_ID}",
    "ben_id": "${BEN_ID}",
    "tech3_in_sales": ${TECH_3_IN_SALES},
    "tech4_in_sales": ${TECH_4_IN_SALES},
    "sales3_in_cs": ${SALES_3_IN_CS},
    "raj_tech_access": ${RAJ_TECH_ACCESS},
    "raj_sales_access": ${RAJ_SALES_ACCESS},
    "ben_sales_access": ${BEN_SALES_ACCESS},
    "ben_cs_access": ${BEN_CS_ACCESS},
    "tech1_assigned_to_raj": ${TECH_1_ASSIGNED_RAJ},
    "tech2_assigned_to_raj": ${TECH_2_ASSIGNED_RAJ},
    "cs1_assigned_to_nina": ${CS_1_ASSIGNED_NINA},
    "cs2_assigned_to_nina": ${CS_2_ASSIGNED_NINA},
    "saved_reply_found": ${SAVED_REPLY_FOUND},
    "saved_reply_name": "${SAVED_REPLY_NAME}",
    "saved_reply_text_preview": "${SAVED_REPLY_TEXT}",
    "nfu_tag_found": ${NFU_TAG_FOUND},
    "tagged_sales_count": ${TAGGED_SALES_COUNT},
    "sales_unresponded_count": ${SALES_UNRESPONDED_COUNT},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
