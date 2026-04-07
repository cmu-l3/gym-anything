#!/bin/bash
echo "=== Setting up confidential_outreach_preparation ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Reset specific folders/files to ensure clean state
rm -f /home/ga/Documents/summit_nominees.txt 2>/dev/null || true
mkdir -p /home/ga/Documents

# 3. Clear Drafts folder to make verification unambiguous
# (Safe to delete cur/new in Maildir structure)
rm -f /home/ga/Maildir/.Drafts/cur/* 2>/dev/null || true
rm -f /home/ga/Maildir/.Drafts/new/* 2>/dev/null || true
rm -f /home/ga/Maildir/.Drafts/tmp/* 2>/dev/null || true

# 4. Ensure BlueMail is running
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
fi

# 5. Wait for window and maximize
wait_for_bluemail_window 60
sleep 2
maximize_bluemail

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="