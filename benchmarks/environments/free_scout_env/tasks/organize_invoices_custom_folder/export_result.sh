#!/bin/bash
echo "=== Exporting organize_invoices_custom_folder result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Retrieve setup data
MAILBOX_ID=$(cat /tmp/sales_mailbox_id.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_SUBJECT="Invoice #2023-998 for December Consultation"
TARGET_FOLDER_NAME="Invoices"

# 1. Check if 'Invoices' folder exists in Sales mailbox
FOLDER_DATA=$(fs_query "SELECT id, created_at FROM folders WHERE mailbox_id = '$MAILBOX_ID' AND name = '$TARGET_FOLDER_NAME' LIMIT 1" 2>/dev/null)
FOLDER_FOUND="false"
FOLDER_ID=""
FOLDER_CREATED_AT=""

if [ -n "$FOLDER_DATA" ]; then
    FOLDER_FOUND="true"
    FOLDER_ID=$(echo "$FOLDER_DATA" | cut -f1)
    FOLDER_CREATED_AT=$(echo "$FOLDER_DATA" | cut -f2)
fi

# 2. Check conversation location
CONV_DATA=$(fs_query "SELECT id, folder_id FROM conversations WHERE mailbox_id = '$MAILBOX_ID' AND subject = '$TARGET_SUBJECT' LIMIT 1" 2>/dev/null)
CONV_FOUND="false"
CONV_ID=""
CURRENT_FOLDER_ID=""

if [ -n "$CONV_DATA" ]; then
    CONV_FOUND="true"
    CONV_ID=$(echo "$CONV_DATA" | cut -f1)
    CURRENT_FOLDER_ID=$(echo "$CONV_DATA" | cut -f2)
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "mailbox_id": "${MAILBOX_ID}",
    "folder_found": ${FOLDER_FOUND},
    "folder_id": "${FOLDER_ID}",
    "folder_created_at": "${FOLDER_CREATED_AT}",
    "conversation_found": ${CONV_FOUND},
    "conversation_id": "${CONV_ID}",
    "current_folder_id": "${CURRENT_FOLDER_ID}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="