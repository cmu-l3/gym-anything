#!/bin/bash
echo "=== Setting up rich_text_digest_authoring ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Ensure Dovecot/Postfix are running
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true
sleep 2

# Clean up Drafts folder to ensure we identify the correct new draft
rm -f /home/ga/Maildir/.Drafts/cur/* 2>/dev/null || true
rm -f /home/ga/Maildir/.Drafts/new/* 2>/dev/null || true
rm -f /home/ga/Maildir/.Drafts/tmp/* 2>/dev/null || true

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window and maximize
wait_for_bluemail_window 60
sleep 2
maximize_bluemail

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="