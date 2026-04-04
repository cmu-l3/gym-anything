#!/bin/bash
echo "=== Setting up organize_emails_into_folders task ==="

source /workspace/scripts/task_utils.sh

# Record initial state
INITIAL_INBOX_COUNT=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Inbox")
echo "$INITIAL_INBOX_COUNT" > /tmp/initial_inbox_count
echo "Initial inbox count: $INITIAL_INBOX_COUNT"

# Record list of initial folders
list_local_folders > /tmp/initial_folders_list
echo "Initial folders:"
cat /tmp/initial_folders_list

# Ensure "Important" folder does NOT exist yet
if folder_exists "Important"; then
    rm -f "${LOCAL_MAIL_DIR}/Important" 2>/dev/null
    rm -f "${LOCAL_MAIL_DIR}/Important.msf" 2>/dev/null
    echo "Removed pre-existing Important folder"
fi

# Start Thunderbird if not running
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30

# Maximize the window
sleep 3
maximize_thunderbird

# Take initial screenshot
take_screenshot /tmp/thunderbird_task_start.png

echo "=== organize_emails_into_folders task setup complete ==="
