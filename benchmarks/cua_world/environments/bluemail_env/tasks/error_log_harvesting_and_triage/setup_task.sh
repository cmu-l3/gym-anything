#!/bin/bash
echo "=== Setting up Error Log Harvesting task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Reset/Clean local state
# Ensure Documents exists but ErrorLogs does not (agent must create it)
mkdir -p /home/ga/Documents
rm -rf /home/ga/Documents/ErrorLogs
rm -f /home/ga/Documents/*.txt

# 3. Reset Maildir state
# Remove the target folder if it exists from previous runs
rm -rf "/home/ga/Maildir/.Processed-Logs"

# Ensure Inbox has data (reload if empty)
# (The base environment usually loads data, but we verify here)
INBOX_COUNT=$(ls /home/ga/Maildir/cur/ 2>/dev/null | wc -l)
if [ "$INBOX_COUNT" -lt 10 ]; then
    echo "Reloading email corpus..."
    /workspace/scripts/setup_bluemail.sh > /dev/null 2>&1
fi

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 4. App State
# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait and maximize
wait_for_bluemail_window 60
maximize_bluemail

# 5. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="