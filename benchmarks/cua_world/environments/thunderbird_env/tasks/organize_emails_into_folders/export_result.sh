#!/bin/bash
echo "=== Exporting organize_emails_into_folders result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/thunderbird_final.png

# ============================================================
# Check if "Important" folder was created and has emails
# ============================================================
INITIAL_INBOX=$(cat /tmp/initial_inbox_count 2>/dev/null || echo "0")
CURRENT_INBOX=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Inbox")

# Check for "Important" folder
FOLDER_CREATED="false"
FOLDER_EMAIL_COUNT=0
FOLDER_PATH=""

# Check direct file
if [ -f "${LOCAL_MAIL_DIR}/Important" ]; then
    FOLDER_CREATED="true"
    FOLDER_EMAIL_COUNT=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Important")
    FOLDER_PATH="${LOCAL_MAIL_DIR}/Important"
fi

# Also check inside .sbd subdirectory (Thunderbird sometimes uses subdirectories)
if [ -d "${LOCAL_MAIL_DIR}/Local Folders.sbd" ]; then
    if [ -f "${LOCAL_MAIL_DIR}/Local Folders.sbd/Important" ]; then
        FOLDER_CREATED="true"
        FOLDER_EMAIL_COUNT=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Local Folders.sbd/Important")
        FOLDER_PATH="${LOCAL_MAIL_DIR}/Local Folders.sbd/Important"
    fi
fi

# Check Inbox.sbd for subfolders
if [ -d "${LOCAL_MAIL_DIR}/Inbox.sbd" ]; then
    if [ -f "${LOCAL_MAIL_DIR}/Inbox.sbd/Important" ]; then
        FOLDER_CREATED="true"
        FOLDER_EMAIL_COUNT=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Inbox.sbd/Important")
        FOLDER_PATH="${LOCAL_MAIL_DIR}/Inbox.sbd/Important"
    fi
fi

# Calculate how many emails were moved from Inbox
EMAILS_MOVED=0
if [ "$CURRENT_INBOX" -lt "$INITIAL_INBOX" ]; then
    EMAILS_MOVED=$((INITIAL_INBOX - CURRENT_INBOX))
fi

# List all current folders
CURRENT_FOLDERS=$(list_local_folders | tr '\n' ',' | sed 's/,$//')

# Check Thunderbird is still running
TB_RUNNING="false"
if is_thunderbird_running; then
    TB_RUNNING="true"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "folder_created": $FOLDER_CREATED,
    "folder_email_count": $FOLDER_EMAIL_COUNT,
    "folder_path": "$FOLDER_PATH",
    "initial_inbox_count": $INITIAL_INBOX,
    "current_inbox_count": $CURRENT_INBOX,
    "emails_moved_from_inbox": $EMAILS_MOVED,
    "current_folders": "$CURRENT_FOLDERS",
    "thunderbird_running": $TB_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
