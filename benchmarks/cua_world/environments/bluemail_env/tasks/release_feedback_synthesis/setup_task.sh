#!/bin/bash
echo "=== Setting up release_feedback_synthesis task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. CLEAN STATE PREPARATION
# ============================================================

MAILDIR="/home/ga/Maildir"

# Ensure BlueMail is running to receive any FS changes later
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window
wait_for_bluemail_window 60
maximize_bluemail

echo "Clearing previous state..."

# 1. Unflag all emails in Inbox (remove 'F' from file suffix)
# Maildir format: unique_name:2,FLAGS (F=Flagged, S=Seen, R=Replied, T=Trashed)
# We want to keep S (Seen) but remove F.
find "$MAILDIR/cur" -name "*:2,*F*" | while read filepath; do
    newpath=$(echo "$filepath" | sed 's/F//g')
    mv "$filepath" "$newpath"
done

# 2. Clear Drafts folder completely
rm -f "$MAILDIR/.Drafts/cur/"* "$MAILDIR/.Drafts/new/"* 2>/dev/null || true

# 3. Ensure we have "Release/Version" content in the inbox
# The SpamAssassin corpus usually has technical content. 
# We'll grep to confirm baseline count for debugging.
KEYWORD_COUNT=$(grep -ilE "release|version|announc" "$MAILDIR/cur/"* 2>/dev/null | wc -l)
echo "Found $KEYWORD_COUNT potential target emails in inbox baseline."

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Give BlueMail a moment to sync the unflagged state
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="