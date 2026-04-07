#!/bin/bash
echo "=== Setting up reply_and_forward task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Dovecot IMAP is running (required for BlueMail)
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true
sleep 2

# Clean Sent and Drafts folders to ensure we verify only new actions
# Note: We preserve the Inbox so the "razor" email remains available
MAILDIR="/home/ga/Maildir"
echo "Cleaning Sent and Drafts folders..."
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Ensure BlueMail is running
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    # Wait for window
    wait_for_bluemail_window 60
fi

# Ensure window is maximized and focused
echo "Maximizing BlueMail..."
maximize_bluemail
sleep 2

# Verify "razor" email exists in inbox (for debugging/validation)
RAZOR_COUNT=$(grep -ri "razor" "${MAILDIR}/cur" "${MAILDIR}/new" | grep -i "Subject:" | wc -l)
echo "Found $RAZOR_COUNT emails containing 'razor' in Subject in Maildir"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="