#!/bin/bash
echo "=== Setting up create_folder task ==="

source /workspace/scripts/task_utils.sh

# Ensure Dovecot IMAP is running
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true
sleep 2

# Ensure BlueMail is running (don't kill existing — preserves account config)
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for BlueMail window to appear
wait_for_bluemail_window 60

# Maximize the window
sleep 3
maximize_bluemail

# Take initial screenshot
take_screenshot /tmp/bluemail_task_start.png

echo "=== create_folder task setup complete ==="
