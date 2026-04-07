#!/bin/bash
set -e
echo "=== Setting up Build Failure Triage Task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Directory definitions
MAILDIR="/home/ga/Maildir"
INBOX_CUR="$MAILDIR/cur"

# 1. Clean up previous task artifacts
echo "Cleaning up previous state..."
rm -rf "$MAILDIR/.Build-Alerts" 2>/dev/null || true
rm -f /home/ga/Documents/triage_log.txt 2>/dev/null || true
# Remove sent items from previous runs to ensure clean verification
rm -f "$MAILDIR/.Sent/cur/"* "$MAILDIR/.Sent/new/"* 2>/dev/null || true

# 2. Inject specific "failure" emails to ensure the task is solvable
# We mix these in with the existing corpus.
echo "Injecting seed emails..."
timestamp=$(date +%s)
hostname=$(hostname)

# Function to create an email
create_email() {
    local subject="$1"
    local from="$2"
    local date_offset="$3" # seconds to subtract
    local filename="${timestamp}_${RANDOM}.${hostname}:2,S" # S flag = Seen (Read)
    
    local date_str=$(date -R -d "@$((timestamp - date_offset))")
    
    cat > "$INBOX_CUR/$filename" <<EOF
Return-Path: <$from>
Delivered-To: ga@example.com
Received: from localhost (localhost [127.0.0.1])
	by $hostname (Postfix) with ESMTP id $RANDOM
	for <ga@example.com>; $date_str
From: $from
To: ga@example.com
Subject: $subject
Date: $date_str
Message-Id: <$RANDOM-$timestamp@example.com>
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii

This is an automated report.
Details regarding: $subject
Timestamp: $date_str
EOF
}

# Inject 4 relevant emails
create_email "[Jenkins] Nightly Build FAILED" "jenkins@techcorp.org" 300
create_email "CRITICAL: Database connection error in prod" "monitor@techcorp.org" 600
create_email "Bug report: UI glitch in dashboard" "qa-lead@techcorp.org" 3600
create_email "Problem with payment gateway API" "support@techcorp.org" 7200

# Inject 2 irrelevant emails to act as distractors
create_email "Lunch meeting rescheduled" "manager@techcorp.org" 1200
create_email "Weekly newsletter" "hr@techcorp.org" 8000

# 3. Force Dovecot to re-index so BlueMail sees them
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Ensure BlueMail is running and ready
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
fi

echo "Waiting for BlueMail window..."
wait_for_bluemail_window 60

echo "Maximizing BlueMail..."
maximize_bluemail
sleep 2

# 6. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="