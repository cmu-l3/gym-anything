#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Allow Thunderbird a moment to flush disk writes
echo "Waiting for Thunderbird to sync files..."
sleep 3

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare verification directory
VERIFY_DIR="/tmp/verify_files"
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"

# Safely copy mbox files for the verifier
if [ -f "${LOCAL_MAIL_DIR}/Inbox" ]; then
    cp "${LOCAL_MAIL_DIR}/Inbox" "$VERIFY_DIR/Inbox"
else
    touch "$VERIFY_DIR/Inbox"
fi

if [ -f "${LOCAL_MAIL_DIR}/Trash" ]; then
    cp "${LOCAL_MAIL_DIR}/Trash" "$VERIFY_DIR/Trash"
else
    touch "$VERIFY_DIR/Trash"
fi

# Fix permissions so copy_from_env can grab them
chmod -R 777 "$VERIFY_DIR"

# Write out task metadata to a JSON
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(cat /tmp/task_end_time.txt 2>/dev/null || echo "0")
INBOX_SIZE=$(stat -c%s "$VERIFY_DIR/Inbox" 2>/dev/null || echo "0")
TRASH_SIZE=$(stat -c%s "$VERIFY_DIR/Trash" 2>/dev/null || echo "0")
TB_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "inbox_size_bytes": $INBOX_SIZE,
    "trash_size_bytes": $TRASH_SIZE,
    "app_was_running": $TB_RUNNING
}
EOF
chmod 666 /tmp/task_result.json

echo "Exported Inbox size: $INBOX_SIZE bytes"
echo "Exported Trash size: $TRASH_SIZE bytes"
echo "=== Export complete ==="