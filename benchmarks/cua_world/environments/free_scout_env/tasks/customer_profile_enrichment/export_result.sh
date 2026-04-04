#!/bin/bash
echo "=== Exporting customer_profile_enrichment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

TECH_MAILBOX_ID=$(cat /tmp/tech_mailbox_id_cpe 2>/dev/null || echo "")
MARISA_ID=$(cat /tmp/marisa_customer_id 2>/dev/null || echo "")
NICOLAS_ID=$(cat /tmp/nicolas_customer_id 2>/dev/null || echo "")
MARISA_CONV_IDS=$(cat /tmp/marisa_conv_ids 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_CUSTOMER_COUNT=$(cat /tmp/initial_customer_count 2>/dev/null || echo "0")

# ---- Check Marisa Obrien profile updates ----
MARISA_COMPANY=""
MARISA_PHONE=""
MARISA_JOB_TITLE=""
if [ -n "$MARISA_ID" ]; then
    MARISA_DATA=$(fs_query "SELECT company, job_title FROM customers WHERE id=$MARISA_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$MARISA_DATA" ]; then
        MARISA_COMPANY=$(echo "$MARISA_DATA" | cut -f1)
        MARISA_JOB_TITLE=$(echo "$MARISA_DATA" | cut -f2)
    fi
    # Check phone (stored in phones table)
    MARISA_PHONE=$(fs_query "SELECT value FROM phones WHERE customer_id=$MARISA_ID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
fi

# ---- Check Nicolas Wilson profile updates ----
NICOLAS_COMPANY=""
NICOLAS_PHONE=""
if [ -n "$NICOLAS_ID" ]; then
    NICOLAS_DATA=$(fs_query "SELECT company FROM customers WHERE id=$NICOLAS_ID LIMIT 1" 2>/dev/null || echo "")
    NICOLAS_COMPANY="$NICOLAS_DATA"
    NICOLAS_PHONE=$(fs_query "SELECT value FROM phones WHERE customer_id=$NICOLAS_ID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
fi

# ---- Check David Okafor created ----
DAVID_FOUND=false
DAVID_ID=""
DAVID_COMPANY=""
DAVID_PHONE=""
DAVID_DATA=$(fs_query "SELECT c.id, c.company FROM customers c JOIN emails e ON c.id=e.customer_id WHERE LOWER(e.email)='david.okafor@techfirm.io' LIMIT 1" 2>/dev/null || echo "")
if [ -n "$DAVID_DATA" ]; then
    DAVID_FOUND=true
    DAVID_ID=$(echo "$DAVID_DATA" | cut -f1)
    DAVID_COMPANY=$(echo "$DAVID_DATA" | cut -f2)
    DAVID_PHONE=$(fs_query "SELECT value FROM phones WHERE customer_id=$DAVID_ID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
fi

# ---- Check Marisa's conversations tagged 'vip-client' ----
TAG_ID=$(fs_query "SELECT id FROM tags WHERE LOWER(name)='vip-client' LIMIT 1" 2>/dev/null || echo "")
MARISA_TAGGED_COUNT=0
if [ -n "$TAG_ID" ] && [ -n "$MARISA_CONV_IDS" ]; then
    IFS=',' read -ra CONV_ARR <<< "$MARISA_CONV_IDS"
    for CONV_ID in "${CONV_ARR[@]}"; do
        CONV_ID=$(echo "$CONV_ID" | tr -d ' ')
        if [ -n "$CONV_ID" ]; then
            CNT=$(fs_query "SELECT COUNT(*) FROM conversation_tag WHERE conversation_id=$CONV_ID AND tag_id=$TAG_ID" 2>/dev/null || echo "0")
            if [ "$CNT" != "0" ]; then
                MARISA_TAGGED_COUNT=$((MARISA_TAGGED_COUNT + 1))
            fi
        fi
    done
fi

# ---- Check new conversation for David Okafor ----
DAVID_CONV_FOUND=false
DAVID_CONV_MAILBOX_CORRECT=false
DAVID_CONV_SUBJECT=""
if [ -n "$TECH_MAILBOX_ID" ]; then
    DAVID_CONV_DATA=$(fs_query "SELECT id, subject, mailbox_id FROM conversations WHERE LOWER(subject) LIKE '%enterprise account onboarding%' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$DAVID_CONV_DATA" ]; then
        DAVID_CONV_FOUND=true
        DAVID_CONV_MAILBOX_ID=$(echo "$DAVID_CONV_DATA" | cut -f3)
        DAVID_CONV_SUBJECT=$(echo "$DAVID_CONV_DATA" | cut -f2)
        if [ "$DAVID_CONV_MAILBOX_ID" = "$TECH_MAILBOX_ID" ]; then
            DAVID_CONV_MAILBOX_CORRECT=true
        fi
    fi
fi

CURRENT_CUSTOMER_COUNT=$(fs_query "SELECT COUNT(*) FROM customers" 2>/dev/null || echo "0")

# Escape for JSON
MARISA_COMPANY=$(echo "$MARISA_COMPANY" | sed 's/"/\\"/g')
MARISA_PHONE=$(echo "$MARISA_PHONE" | sed 's/"/\\"/g')
MARISA_JOB_TITLE=$(echo "$MARISA_JOB_TITLE" | sed 's/"/\\"/g')
NICOLAS_COMPANY=$(echo "$NICOLAS_COMPANY" | sed 's/"/\\"/g')
NICOLAS_PHONE=$(echo "$NICOLAS_PHONE" | sed 's/"/\\"/g')
DAVID_COMPANY=$(echo "$DAVID_COMPANY" | sed 's/"/\\"/g')
DAVID_PHONE=$(echo "$DAVID_PHONE" | sed 's/"/\\"/g')
DAVID_CONV_SUBJECT=$(echo "$DAVID_CONV_SUBJECT" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": ${TASK_START},
    "initial_customer_count": ${INITIAL_CUSTOMER_COUNT},
    "current_customer_count": ${CURRENT_CUSTOMER_COUNT},
    "marisa_company": "${MARISA_COMPANY}",
    "marisa_phone": "${MARISA_PHONE}",
    "marisa_job_title": "${MARISA_JOB_TITLE}",
    "nicolas_company": "${NICOLAS_COMPANY}",
    "nicolas_phone": "${NICOLAS_PHONE}",
    "david_found": ${DAVID_FOUND},
    "david_id": "${DAVID_ID}",
    "david_company": "${DAVID_COMPANY}",
    "david_phone": "${DAVID_PHONE}",
    "marisa_tagged_count": ${MARISA_TAGGED_COUNT},
    "david_conv_found": ${DAVID_CONV_FOUND},
    "david_conv_mailbox_correct": ${DAVID_CONV_MAILBOX_CORRECT},
    "david_conv_subject": "${DAVID_CONV_SUBJECT}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
