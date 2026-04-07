#!/bin/bash
echo "=== Setting up create_message_filter task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed so we can modify the mbox files cleanly
close_thunderbird
sleep 2

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_FILE="${LOCAL_MAIL_DIR}/Inbox"

# Ensure clean state (no pre-existing folder or rules)
rm -f "${LOCAL_MAIL_DIR}/ProjectAlpha"
rm -f "${LOCAL_MAIL_DIR}/ProjectAlpha.msf"
rm -f "${PROFILE_DIR}/msgFilterRules.dat"

echo "Injecting sample emails into Inbox..."
for i in {1..5}; do
  DATE_STR=$(date -R -d "-${i} hours")
  SUBJECTS=(
    "Project Alpha: Q3 Budget Review Meeting"
    "Re: Project Alpha milestone update - Phase 2 complete"
    "Project Alpha team standup notes (Week 23)"
    "FYI: Project Alpha vendor contract renewal"
    "Project Alpha: Action items from Monday sync"
  )
  SUBJ="${SUBJECTS[$((i-1))]}"
  
  cat >> "$INBOX_FILE" << EOF
From sender@example.com $(date -d "-${i} hours" +"%a %b %d %H:%M:%S %Y")
Return-Path: <sender@example.com>
Date: $DATE_STR
From: Sender <sender@example.com>
To: ga@example.com
Subject: $SUBJ
Message-ID: <test-alpha-${i}@example.com>
Content-Type: text/plain; charset=UTF-8

This is a test email about Project Alpha.
Please review the attached notes.
Regards,
Sender

EOF
done

# Remove the Inbox index so Thunderbird rebuilds it with our injected emails
rm -f "${LOCAL_MAIL_DIR}/Inbox.msf"

# Record initial counts
INITIAL_INBOX_COUNT=$(count_emails_in_mbox "$INBOX_FILE")
echo "$INITIAL_INBOX_COUNT" > /tmp/initial_inbox_count.txt

# Start Thunderbird with the newly injected data
echo "Starting Thunderbird..."
start_thunderbird

# Wait and maximize
wait_for_thunderbird_window 30
maximize_thunderbird

sleep 2

# Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="