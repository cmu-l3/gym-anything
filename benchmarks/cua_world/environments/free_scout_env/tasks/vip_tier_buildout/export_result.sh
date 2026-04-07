#!/bin/bash
echo "=== Exporting vip_tier_buildout result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Load stored IDs
GENERAL_MAILBOX_ID=$(cat /tmp/general_mailbox_id_vtb 2>/dev/null || echo "")
TEMP_ID=$(cat /tmp/temp_worker_id_vtb 2>/dev/null || echo "")
CONV1_ID=$(cat /tmp/conv_1_id_vtb 2>/dev/null || echo "")
CONV2_ID=$(cat /tmp/conv_2_id_vtb 2>/dev/null || echo "")
CONV3_ID=$(cat /tmp/conv_3_id_vtb 2>/dev/null || echo "")
CONV4_ID=$(cat /tmp/conv_4_id_vtb 2>/dev/null || echo "")
CONV5_ID=$(cat /tmp/conv_5_id_vtb 2>/dev/null || echo "")
CONV6_ID=$(cat /tmp/conv_6_id_vtb 2>/dev/null || echo "")
PINNACLE_CUST_ID=$(cat /tmp/pinnacle_customer_id_vtb 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

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
echo "VIP mailbox found: $VIP_MAILBOX_FOUND (ID: $VIP_MAILBOX_ID, Name: $VIP_MAILBOX_NAME)"

# ---- Check Jordan Mitchell ----
JORDAN_DATA=$(fs_query "SELECT id, first_name, last_name, role FROM users WHERE LOWER(email)='jordan.mitchell@helpdesk.local' LIMIT 1" 2>/dev/null || echo "")
JORDAN_FOUND=false
JORDAN_ID=""
JORDAN_ROLE=0
if [ -n "$JORDAN_DATA" ]; then
    JORDAN_FOUND=true
    JORDAN_ID=$(echo "$JORDAN_DATA" | cut -f1)
    JORDAN_ROLE=$(echo "$JORDAN_DATA" | cut -f4)
fi
echo "Jordan found: $JORDAN_FOUND (ID: $JORDAN_ID, Role: $JORDAN_ROLE)"

# ---- Check Jordan's mailbox access ----
JORDAN_VIP_ACCESS=false
JORDAN_TOTAL_MAILBOXES=0
if [ -n "$JORDAN_ID" ]; then
    if [ -n "$VIP_MAILBOX_ID" ]; then
        CNT=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$JORDAN_ID AND mailbox_id=$VIP_MAILBOX_ID" 2>/dev/null || echo "0")
        [ "$CNT" != "0" ] && JORDAN_VIP_ACCESS=true
    fi
    JORDAN_TOTAL_MAILBOXES=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE user_id=$JORDAN_ID" 2>/dev/null || echo "0")
fi
echo "Jordan VIP access: $JORDAN_VIP_ACCESS, total mailboxes: $JORDAN_TOTAL_MAILBOXES"

# ---- Check conversation routing (enterprise convs should be in VIP) ----
CONV1_MAILBOX=""
CONV2_MAILBOX=""
CONV3_MAILBOX=""
CONV4_MAILBOX=""
CONV5_MAILBOX=""
CONV6_MAILBOX=""
CONV1_IN_VIP=false
CONV2_IN_VIP=false
CONV3_IN_VIP=false
CONV4_IN_GENERAL=false
CONV5_IN_GENERAL=false
CONV6_IN_GENERAL=false

for i in 1 2 3 4 5 6; do
    CID_VAR="CONV${i}_ID"
    CID=$(eval echo "\$$CID_VAR")
    if [ -n "$CID" ]; then
        MBX=$(fs_query "SELECT mailbox_id FROM conversations WHERE id=$CID LIMIT 1" 2>/dev/null || echo "")
        eval "CONV${i}_MAILBOX=$MBX"
    fi
done

[ -n "$VIP_MAILBOX_ID" ] && [ "$CONV1_MAILBOX" = "$VIP_MAILBOX_ID" ] && CONV1_IN_VIP=true
[ -n "$VIP_MAILBOX_ID" ] && [ "$CONV2_MAILBOX" = "$VIP_MAILBOX_ID" ] && CONV2_IN_VIP=true
[ -n "$VIP_MAILBOX_ID" ] && [ "$CONV3_MAILBOX" = "$VIP_MAILBOX_ID" ] && CONV3_IN_VIP=true
[ -n "$GENERAL_MAILBOX_ID" ] && [ "$CONV4_MAILBOX" = "$GENERAL_MAILBOX_ID" ] && CONV4_IN_GENERAL=true
[ -n "$GENERAL_MAILBOX_ID" ] && [ "$CONV5_MAILBOX" = "$GENERAL_MAILBOX_ID" ] && CONV5_IN_GENERAL=true
[ -n "$GENERAL_MAILBOX_ID" ] && [ "$CONV6_MAILBOX" = "$GENERAL_MAILBOX_ID" ] && CONV6_IN_GENERAL=true

echo "Conv1 in VIP: $CONV1_IN_VIP, Conv2 in VIP: $CONV2_IN_VIP, Conv3 in VIP: $CONV3_IN_VIP"
echo "Conv4 in General: $CONV4_IN_GENERAL, Conv5 in General: $CONV5_IN_GENERAL, Conv6 in General: $CONV6_IN_GENERAL"

# ---- Check conversation assignments to Jordan ----
CONV1_ASSIGNED_JORDAN=false
CONV2_ASSIGNED_JORDAN=false
CONV3_ASSIGNED_JORDAN=false
if [ -n "$JORDAN_ID" ]; then
    for i in 1 2 3; do
        CID_VAR="CONV${i}_ID"
        CID=$(eval echo "\$$CID_VAR")
        if [ -n "$CID" ]; then
            ASSIGNED=$(fs_query "SELECT IFNULL(user_id, 0) FROM conversations WHERE id=$CID LIMIT 1" 2>/dev/null || echo "0")
            [ "$ASSIGNED" = "$JORDAN_ID" ] && eval "CONV${i}_ASSIGNED_JORDAN=true"
        fi
    done
fi
echo "Conv1 assigned Jordan: $CONV1_ASSIGNED_JORDAN, Conv2: $CONV2_ASSIGNED_JORDAN, Conv3: $CONV3_ASSIGNED_JORDAN"

# ---- Check auto-reply on VIP mailbox ----
AUTO_REPLY_ENABLED=false
AUTO_REPLY_SUBJECT=""
AUTO_REPLY_MESSAGE=""
if [ -n "$VIP_MAILBOX_ID" ]; then
    AR_ENABLED=$(fs_query "SELECT auto_reply_enabled FROM mailboxes WHERE id=$VIP_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "0")
    [ "$AR_ENABLED" = "1" ] && AUTO_REPLY_ENABLED=true
    AUTO_REPLY_SUBJECT=$(fs_query "SELECT auto_reply_subject FROM mailboxes WHERE id=$VIP_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
    AUTO_REPLY_MESSAGE=$(fs_query "SELECT auto_reply_message FROM mailboxes WHERE id=$VIP_MAILBOX_ID LIMIT 1" 2>/dev/null || echo "")
fi
echo "Auto-reply enabled: $AUTO_REPLY_ENABLED, subject: $AUTO_REPLY_SUBJECT"

# ---- Check Conv 1 reopened (status should be Active=1, was Closed=3) ----
CONV1_STATUS=""
CONV1_REOPENED=false
if [ -n "$CONV1_ID" ]; then
    CONV1_STATUS=$(fs_query "SELECT status FROM conversations WHERE id=$CONV1_ID LIMIT 1" 2>/dev/null || echo "")
    [ "$CONV1_STATUS" = "1" ] && CONV1_REOPENED=true
fi
echo "Conv1 status: $CONV1_STATUS, reopened: $CONV1_REOPENED"

# ---- Check internal note on Conv 1 ----
CONV1_HAS_NOTE=false
CONV1_NOTE_TEXT=""
if [ -n "$CONV1_ID" ]; then
    # type=2 is note in FreeScout threads
    NOTE_DATA=$(fs_query "SELECT body FROM threads WHERE conversation_id=$CONV1_ID AND type=2 AND UNIX_TIMESTAMP(created_at) > $TASK_START ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$NOTE_DATA" ]; then
        CONV1_HAS_NOTE=true
        CONV1_NOTE_TEXT="$NOTE_DATA"
    fi
fi
echo "Conv1 has note: $CONV1_HAS_NOTE"

# ---- Check agent reply on Conv 1 (type=3 is message/reply) ----
CONV1_HAS_REPLY=false
CONV1_REPLY_TEXT=""
if [ -n "$CONV1_ID" ]; then
    # In FreeScout, type=1 is customer message, type=2 is note, type=3 is agent reply (varies by version)
    # Check for any non-note, non-customer thread created after task start
    REPLY_DATA=$(fs_query "SELECT body FROM threads WHERE conversation_id=$CONV1_ID AND type != 1 AND type != 2 AND UNIX_TIMESTAMP(created_at) > $TASK_START ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$REPLY_DATA" ]; then
        # Fallback: check for agent-authored threads that are not notes or customer messages
        REPLY_DATA=$(fs_query "SELECT body FROM threads WHERE conversation_id=$CONV1_ID AND user_id IS NOT NULL AND type != 1 AND type != 2 AND UNIX_TIMESTAMP(created_at) > $TASK_START ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
    fi
    if [ -n "$REPLY_DATA" ]; then
        CONV1_HAS_REPLY=true
        CONV1_REPLY_TEXT="$REPLY_DATA"
    fi
fi
echo "Conv1 has reply: $CONV1_HAS_REPLY"

# ---- Check customer profile update ----
CUST_COMPANY=""
CUST_PHONE=""
CUST_COMPANY_CORRECT=false
CUST_PHONE_CORRECT=false
if [ -n "$PINNACLE_CUST_ID" ]; then
    CUST_COMPANY=$(fs_query "SELECT IFNULL(company, '') FROM customers WHERE id=$PINNACLE_CUST_ID LIMIT 1" 2>/dev/null || echo "")
    CUST_PHONE=$(fs_query "SELECT IFNULL(phones, '') FROM customers WHERE id=$PINNACLE_CUST_ID LIMIT 1" 2>/dev/null || echo "")
    echo "$CUST_COMPANY" | grep -qi "pinnacle" && CUST_COMPANY_CORRECT=true
    echo "$CUST_PHONE" | grep -q "415.*555.*0192" && CUST_PHONE_CORRECT=true
fi
echo "Customer company: '$CUST_COMPANY' (correct: $CUST_COMPANY_CORRECT)"
echo "Customer phone: '$CUST_PHONE' (correct: $CUST_PHONE_CORRECT)"

# ---- Check Temp Worker deactivated ----
TEMP_STATUS=""
TEMP_DEACTIVATED=false
TEMP_DELETED=false
if [ -n "$TEMP_ID" ]; then
    TEMP_STATUS=$(fs_query "SELECT status FROM users WHERE id=$TEMP_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$TEMP_STATUS" ]; then
        TEMP_DELETED=true
    elif [ "$TEMP_STATUS" = "2" ] || [ "$TEMP_STATUS" = "3" ]; then
        TEMP_DEACTIVATED=true
    fi
fi
echo "Temp Worker status: $TEMP_STATUS (deactivated: $TEMP_DEACTIVATED, deleted: $TEMP_DELETED)"

# ---- Escape strings for JSON ----
VIP_MAILBOX_NAME=$(echo "$VIP_MAILBOX_NAME" | sed 's/"/\\"/g')
AUTO_REPLY_SUBJECT=$(echo "$AUTO_REPLY_SUBJECT" | sed 's/"/\\"/g')
AUTO_REPLY_MESSAGE=$(echo "$AUTO_REPLY_MESSAGE" | head -c 1000 | sed 's/"/\\"/g' | tr '\n' ' ')
CONV1_NOTE_TEXT=$(echo "$CONV1_NOTE_TEXT" | head -c 500 | sed 's/"/\\"/g' | tr '\n' ' ')
CONV1_REPLY_TEXT=$(echo "$CONV1_REPLY_TEXT" | head -c 500 | sed 's/"/\\"/g' | tr '\n' ' ')
CUST_COMPANY=$(echo "$CUST_COMPANY" | sed 's/"/\\"/g')
CUST_PHONE=$(echo "$CUST_PHONE" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": ${TASK_START},
    "general_mailbox_id": "${GENERAL_MAILBOX_ID}",
    "vip_mailbox_found": ${VIP_MAILBOX_FOUND},
    "vip_mailbox_id": "${VIP_MAILBOX_ID}",
    "vip_mailbox_name": "${VIP_MAILBOX_NAME}",
    "jordan_found": ${JORDAN_FOUND},
    "jordan_id": "${JORDAN_ID}",
    "jordan_role": ${JORDAN_ROLE:-0},
    "jordan_vip_access": ${JORDAN_VIP_ACCESS},
    "jordan_total_mailboxes": ${JORDAN_TOTAL_MAILBOXES:-0},
    "conv1_in_vip": ${CONV1_IN_VIP},
    "conv2_in_vip": ${CONV2_IN_VIP},
    "conv3_in_vip": ${CONV3_IN_VIP},
    "conv4_in_general": ${CONV4_IN_GENERAL},
    "conv5_in_general": ${CONV5_IN_GENERAL},
    "conv6_in_general": ${CONV6_IN_GENERAL},
    "conv1_assigned_jordan": ${CONV1_ASSIGNED_JORDAN},
    "conv2_assigned_jordan": ${CONV2_ASSIGNED_JORDAN},
    "conv3_assigned_jordan": ${CONV3_ASSIGNED_JORDAN},
    "auto_reply_enabled": ${AUTO_REPLY_ENABLED},
    "auto_reply_subject": "${AUTO_REPLY_SUBJECT}",
    "auto_reply_message": "${AUTO_REPLY_MESSAGE}",
    "conv1_reopened": ${CONV1_REOPENED},
    "conv1_status": "${CONV1_STATUS}",
    "conv1_has_note": ${CONV1_HAS_NOTE},
    "conv1_note_text": "${CONV1_NOTE_TEXT}",
    "conv1_has_reply": ${CONV1_HAS_REPLY},
    "conv1_reply_text": "${CONV1_REPLY_TEXT}",
    "customer_company": "${CUST_COMPANY}",
    "customer_phone": "${CUST_PHONE}",
    "customer_company_correct": ${CUST_COMPANY_CORRECT},
    "customer_phone_correct": ${CUST_PHONE_CORRECT},
    "temp_worker_deactivated": ${TEMP_DEACTIVATED},
    "temp_worker_deleted": ${TEMP_DELETED},
    "temp_worker_status": "${TEMP_STATUS}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
