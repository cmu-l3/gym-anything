#!/bin/bash
echo "=== Exporting team_restructuring_and_permissions result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

ALEX_ID=$(cat /tmp/alex_user_id 2>/dev/null || echo "")
MARIA_ID=$(cat /tmp/maria_user_id 2>/dev/null || echo "")
GENERAL_MAILBOX_ID=$(cat /tmp/general_mailbox_id_trp 2>/dev/null || echo "")
TECH_MAILBOX_ID=$(cat /tmp/tech_mailbox_id_trp 2>/dev/null || echo "")
BILLING_MAILBOX_ID=$(cat /tmp/billing_mailbox_id_trp 2>/dev/null || echo "")
VIP_TAG_ID=$(cat /tmp/vip_tag_id 2>/dev/null || echo "")
VIP_CONV_IDS_RAW=$(cat /tmp/vip_conv_ids 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_MAILBOX_COUNT=$(cat /tmp/initial_mailbox_count_trp 2>/dev/null || echo "0")
INITIAL_SAVED_REPLY_COUNT=$(cat /tmp/initial_saved_reply_count_trp 2>/dev/null || echo "0")

# ---- Check VIP Support mailbox ----
VIP_MAILBOX_DATA=$(fs_query "SELECT id, name, email FROM mailboxes WHERE LOWER(email)='vip@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
VIP_MAILBOX_FOUND=false
VIP_MAILBOX_ID=""
VIP_MAILBOX_NAME=""
if [ -n "$VIP_MAILBOX_DATA" ]; then
    VIP_MAILBOX_FOUND=true
    VIP_MAILBOX_ID=$(echo "$VIP_MAILBOX_DATA" | cut -f1)
    VIP_MAILBOX_NAME=$(echo "$VIP_MAILBOX_DATA" | cut -f2)
fi
echo "VIP mailbox found: $VIP_MAILBOX_FOUND (ID: $VIP_MAILBOX_ID)"

# ---- Check Alex Chen's permissions ----
# Alex should have LOST Billing access and GAINED VIP Support access
ALEX_BILLING_ACCESS=false
ALEX_VIP_ACCESS=false
ALEX_GENERAL_ACCESS=false
ALEX_TECH_ACCESS=false

if [ -n "$ALEX_ID" ]; then
    if [ -n "$BILLING_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$ALEX_ID AND mailbox_id=$BILLING_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && ALEX_BILLING_ACCESS=true
    fi
    if [ -n "$VIP_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$ALEX_ID AND mailbox_id=$VIP_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && ALEX_VIP_ACCESS=true
    fi
    if [ -n "$GENERAL_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$ALEX_ID AND mailbox_id=$GENERAL_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && ALEX_GENERAL_ACCESS=true
    fi
    if [ -n "$TECH_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$ALEX_ID AND mailbox_id=$TECH_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && ALEX_TECH_ACCESS=true
    fi
fi
echo "Alex billing access: $ALEX_BILLING_ACCESS, VIP access: $ALEX_VIP_ACCESS"

# ---- Check Maria Rodriguez's permissions ----
# Maria should GAIN Technical + VIP access (already has General)
MARIA_GENERAL_ACCESS=false
MARIA_TECH_ACCESS=false
MARIA_VIP_ACCESS=false
MARIA_BILLING_ACCESS=false

if [ -n "$MARIA_ID" ]; then
    if [ -n "$GENERAL_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$MARIA_ID AND mailbox_id=$GENERAL_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && MARIA_GENERAL_ACCESS=true
    fi
    if [ -n "$TECH_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$MARIA_ID AND mailbox_id=$TECH_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && MARIA_TECH_ACCESS=true
    fi
    if [ -n "$VIP_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$MARIA_ID AND mailbox_id=$VIP_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && MARIA_VIP_ACCESS=true
    fi
    if [ -n "$BILLING_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$MARIA_ID AND mailbox_id=$BILLING_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && MARIA_BILLING_ACCESS=true
    fi
fi
echo "Maria tech access: $MARIA_TECH_ACCESS, VIP access: $MARIA_VIP_ACCESS"

# ---- Check saved reply "VIP Priority Response" ----
SAVED_REPLY_DATA=$(fs_query "SELECT id, name FROM saved_replies WHERE LOWER(name) LIKE '%vip%' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
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

# ---- Count VIP-tagged conversations now in VIP Support mailbox ----
# Check each of the 4 original VIP conversation IDs
VIP_CONVS_MOVED=0
VIP_CONV_SUBJECTS=""

if [ -n "$VIP_MAILBOX_ID" ] && [ -n "$VIP_TAG_ID" ]; then
    VIP_CONVS_MOVED=$(fs_query "SELECT COUNT(*) FROM conversations c JOIN conversation_tag ct ON c.id=ct.conversation_id WHERE c.mailbox_id=$VIP_MAILBOX_ID AND ct.tag_id=$VIP_TAG_ID" 2>/dev/null || echo "0")
    SUBJECTS=$(fs_query "SELECT c.subject FROM conversations c JOIN conversation_tag ct ON c.id=ct.conversation_id WHERE c.mailbox_id=$VIP_MAILBOX_ID AND ct.tag_id=$VIP_TAG_ID" 2>/dev/null || echo "")
    VIP_CONV_SUBJECTS=$(echo "$SUBJECTS" | tr '\n' '|' | head -c 300)
fi
echo "VIP conversations moved to VIP Support: $VIP_CONVS_MOVED"

# ---- Count VIP Support conversations assigned to Alex Chen ----
VIP_ASSIGNED_TO_ALEX=0
if [ -n "$VIP_MAILBOX_ID" ] && [ -n "$ALEX_ID" ]; then
    VIP_ASSIGNED_TO_ALEX=$(fs_query "SELECT COUNT(*) FROM conversations WHERE mailbox_id=$VIP_MAILBOX_ID AND user_id=$ALEX_ID" 2>/dev/null || echo "0")
fi
echo "VIP Support conversations assigned to Alex: $VIP_ASSIGNED_TO_ALEX"

# ---- Total VIP Support conversations (for context) ----
VIP_MAILBOX_TOTAL_CONVS=0
if [ -n "$VIP_MAILBOX_ID" ]; then
    VIP_MAILBOX_TOTAL_CONVS=$(fs_query "SELECT COUNT(*) FROM conversations WHERE mailbox_id=$VIP_MAILBOX_ID" 2>/dev/null || echo "0")
fi

CURRENT_MAILBOX_COUNT=$(fs_query "SELECT COUNT(*) FROM mailboxes" 2>/dev/null || echo "0")
CURRENT_SAVED_REPLY_COUNT=$(fs_query "SELECT COUNT(*) FROM saved_replies" 2>/dev/null || echo "0")

# Escape strings for JSON
VIP_MAILBOX_NAME=$(echo "$VIP_MAILBOX_NAME" | sed 's/"/\\"/g')
SAVED_REPLY_NAME=$(echo "$SAVED_REPLY_NAME" | sed 's/"/\\"/g')
SAVED_REPLY_TEXT=$(echo "$SAVED_REPLY_TEXT" | head -c 500 | sed 's/"/\\"/g' | tr '\n' ' ')
VIP_CONV_SUBJECTS=$(echo "$VIP_CONV_SUBJECTS" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": ${TASK_START},
    "initial_mailbox_count": ${INITIAL_MAILBOX_COUNT},
    "current_mailbox_count": ${CURRENT_MAILBOX_COUNT},
    "initial_saved_reply_count": ${INITIAL_SAVED_REPLY_COUNT},
    "current_saved_reply_count": ${CURRENT_SAVED_REPLY_COUNT},
    "vip_mailbox_found": ${VIP_MAILBOX_FOUND},
    "vip_mailbox_id": "${VIP_MAILBOX_ID}",
    "vip_mailbox_name": "${VIP_MAILBOX_NAME}",
    "alex_id": "${ALEX_ID}",
    "alex_billing_access": ${ALEX_BILLING_ACCESS},
    "alex_vip_access": ${ALEX_VIP_ACCESS},
    "alex_general_access": ${ALEX_GENERAL_ACCESS},
    "alex_tech_access": ${ALEX_TECH_ACCESS},
    "maria_id": "${MARIA_ID}",
    "maria_general_access": ${MARIA_GENERAL_ACCESS},
    "maria_tech_access": ${MARIA_TECH_ACCESS},
    "maria_vip_access": ${MARIA_VIP_ACCESS},
    "maria_billing_access": ${MARIA_BILLING_ACCESS},
    "saved_reply_found": ${SAVED_REPLY_FOUND},
    "saved_reply_name": "${SAVED_REPLY_NAME}",
    "saved_reply_text_preview": "${SAVED_REPLY_TEXT}",
    "vip_convs_moved_count": ${VIP_CONVS_MOVED},
    "vip_conv_subjects": "${VIP_CONV_SUBJECTS}",
    "vip_assigned_to_alex": ${VIP_ASSIGNED_TO_ALEX},
    "vip_mailbox_total_convs": ${VIP_MAILBOX_TOTAL_CONVS},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
