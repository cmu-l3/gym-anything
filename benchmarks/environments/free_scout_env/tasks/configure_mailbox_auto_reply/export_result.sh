#!/bin/bash
echo "=== Exporting configure_mailbox_auto_reply result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Get target mailbox ID
MAILBOX_ID=$(cat /tmp/target_mailbox_id.txt 2>/dev/null)
if [ -z "$MAILBOX_ID" ]; then
    # Fallback search
    MAILBOX_ID=$(find_mailbox_by_name "IT Support" | cut -f1)
fi

# 4. Query current configuration from Database
echo "Querying mailbox configuration..."

# Get enabled status
AR_ENABLED=$(fs_query "SELECT auto_reply_enabled FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null || echo "0")

# Get subject
AR_SUBJECT=$(fs_query "SELECT auto_reply_subject FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null || echo "")

# Get message body
AR_MESSAGE=$(fs_query "SELECT auto_reply_message FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null || echo "")

# Get last update timestamp of the mailbox record to verify it changed *during* the task
# FreeScout updates 'updated_at' when settings change
MAILBOX_UPDATED_AT=$(fs_query "SELECT UNIX_TIMESTAMP(updated_at) FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null || echo "0")

# 5. Check if update happened during task
CONFIG_UPDATED_DURING_TASK="false"
if [ "$MAILBOX_UPDATED_AT" -gt "$TASK_START" ]; then
    CONFIG_UPDATED_DURING_TASK="true"
fi

# 6. Escape strings for JSON safety
AR_SUBJECT_SAFE=$(echo "$AR_SUBJECT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
AR_MESSAGE_SAFE=$(echo "$AR_MESSAGE" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mailbox_id": "${MAILBOX_ID}",
    "auto_reply_enabled": ${AR_ENABLED:-0},
    "auto_reply_subject": "${AR_SUBJECT_SAFE}",
    "auto_reply_message": "${AR_MESSAGE_SAFE}",
    "config_updated_during_task": ${CONFIG_UPDATED_DURING_TASK},
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# 8. Save to final location
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="