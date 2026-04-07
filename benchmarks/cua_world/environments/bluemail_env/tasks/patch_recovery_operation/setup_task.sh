#!/bin/bash
echo "=== Setting up patch_recovery_operation ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. CLEANUP: Remove artifacts from previous runs
echo "Cleaning up previous artifacts..."
rm -rf /home/ga/Documents/patches
rm -rf /home/ga/Maildir/.Pending-Patches 2>/dev/null || true

# Remove draft emails to release-lead from previous runs
grep -l "release-lead@company.com" /home/ga/Maildir/.Drafts/cur/* 2>/dev/null | xargs rm -f
grep -l "release-lead@company.com" /home/ga/Maildir/.Drafts/new/* 2>/dev/null | xargs rm -f

# 2. DATA PREP: Ensure patch emails exist in Inbox
# The environment loads real SpamAssassin data. We check if enough "patch-like" emails exist.
MAILDIR="/home/ga/Maildir"
INBOX_CUR="$MAILDIR/cur"

# Pattern to identify patch emails
PATCH_PATTERN="\[PATCH\]|diff --git|Index: "

echo "Scanning for patch emails..."
PATCH_COUNT=$(grep -lE "$PATCH_PATTERN" "$INBOX_CUR"/* 2>/dev/null | wc -l)
echo "Found $PATCH_COUNT existing patch emails."

# If fewer than 5 patches, we duplicate some existing ones to ensure the task is solvable
if [ "$PATCH_COUNT" -lt 5 ]; then
    echo "Injecting additional patch emails to ensure task solvability..."
    # Find at least one patch email source or use a fallback if absolutely none exist
    SOURCE_PATCH=$(grep -lE "$PATCH_PATTERN" "$INBOX_CUR"/* 2>/dev/null | head -1)
    
    # If we found a source, duplicate it with different timestamps
    if [ -n "$SOURCE_PATCH" ]; then
        for i in {1..5}; do
            NEW_NAME="$(date +%s)_$i.injected.$(hostname):2,S"
            cp "$SOURCE_PATCH" "$INBOX_CUR/$NEW_NAME"
        done
        # Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
        reset_dovecot_indexes
    fi
fi

# 3. APP SETUP: Ensure BlueMail is running and ready
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window
wait_for_bluemail_window 60

# Maximize
sleep 2
maximize_bluemail

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="