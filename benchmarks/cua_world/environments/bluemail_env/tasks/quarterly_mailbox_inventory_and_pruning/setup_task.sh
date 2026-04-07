#!/bin/bash
set -e
echo "=== Setting up quarterly_mailbox_inventory_and_pruning task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Ensure mail servers are running
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true
systemctl restart postfix 2>/dev/null || true
sleep 3

# ============================================================
# Reset Maildir to known state
# ============================================================
MAILDIR="/home/ga/Maildir"

# Clear any custom folders from previous runs (keep defaults)
find "$MAILDIR" -maxdepth 1 -type d -name '.*' \
    ! -name '.Junk' ! -name '.Drafts' ! -name '.Sent' ! -name '.Trash' \
    ! -name '.' ! -name '..' \
    -exec rm -rf {} + 2>/dev/null || true

# Clear all folders content
rm -f "$MAILDIR/cur/"* "$MAILDIR/new/"* "$MAILDIR/tmp/"* 2>/dev/null || true
rm -f "$MAILDIR/.Junk/cur/"* "$MAILDIR/.Junk/new/"* "$MAILDIR/.Junk/tmp/"* 2>/dev/null || true
rm -f "$MAILDIR/.Drafts/cur/"* "$MAILDIR/.Drafts/new/"* "$MAILDIR/.Drafts/tmp/"* 2>/dev/null || true
rm -f "$MAILDIR/.Sent/cur/"* "$MAILDIR/.Sent/new/"* "$MAILDIR/.Sent/tmp/"* 2>/dev/null || true
rm -f "$MAILDIR/.Trash/cur/"* "$MAILDIR/.Trash/new/"* "$MAILDIR/.Trash/tmp/"* 2>/dev/null || true

# Ensure folder structures exist
for folder in "" .Junk .Drafts .Sent .Trash; do
    mkdir -p "$MAILDIR/$folder/cur" "$MAILDIR/$folder/new" "$MAILDIR/$folder/tmp"
done

# ============================================================
# Populate Inbox with 50 ham emails
# ============================================================
EMAIL_COUNT=0
if [ -d "/workspace/assets/emails/ham" ]; then
    # Use glob expansion to get exactly 50 if possible, or loop
    # We use a loop with counter to be safe
    for eml_file in /workspace/assets/emails/ham/*.eml; do
        if [ -f "$eml_file" ] && [ $EMAIL_COUNT -lt 50 ]; then
            TIMESTAMP=$(date +%s)
            UNIQUE="${TIMESTAMP}.${EMAIL_COUNT}.$(hostname)"
            cp "$eml_file" "$MAILDIR/cur/${UNIQUE}:2,S"
            EMAIL_COUNT=$((EMAIL_COUNT + 1))
        fi
        [ $EMAIL_COUNT -ge 50 ] && break
    done
fi
echo "Loaded $EMAIL_COUNT ham emails into Inbox"

# ============================================================
# Populate Junk with 10 spam emails
# ============================================================
SPAM_COUNT=0
if [ -d "/workspace/assets/emails/spam" ]; then
    for eml_file in /workspace/assets/emails/spam/*.eml; do
        if [ -f "$eml_file" ] && [ $SPAM_COUNT -lt 10 ]; then
            TIMESTAMP=$(date +%s)
            UNIQUE="${TIMESTAMP}.spam${SPAM_COUNT}.$(hostname)"
            cp "$eml_file" "$MAILDIR/.Junk/cur/${UNIQUE}:2,S"
            SPAM_COUNT=$((SPAM_COUNT + 1))
        fi
        [ $SPAM_COUNT -ge 10 ] && break
    done
fi
echo "Loaded $SPAM_COUNT spam emails into Junk"

# Fix permissions
chown -R ga:ga "$MAILDIR"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# Record initial folder counts (ground truth)
# ============================================================
INBOX_COUNT=$(ls -1 "$MAILDIR/cur/" "$MAILDIR/new/" 2>/dev/null | wc -l)
JUNK_COUNT=$(ls -1 "$MAILDIR/.Junk/cur/" "$MAILDIR/.Junk/new/" 2>/dev/null | wc -l)
DRAFTS_COUNT=$(ls -1 "$MAILDIR/.Drafts/cur/" "$MAILDIR/.Drafts/new/" 2>/dev/null | wc -l)
SENT_COUNT=$(ls -1 "$MAILDIR/.Sent/cur/" "$MAILDIR/.Sent/new/" 2>/dev/null | wc -l)
TRASH_COUNT=$(ls -1 "$MAILDIR/.Trash/cur/" "$MAILDIR/.Trash/new/" 2>/dev/null | wc -l)

cat > /tmp/initial_folder_counts.json << EOF
{
    "inbox": $INBOX_COUNT,
    "junk": $JUNK_COUNT,
    "drafts": $DRAFTS_COUNT,
    "sent": $SENT_COUNT,
    "trash": $TRASH_COUNT,
    "total": $((INBOX_COUNT + JUNK_COUNT + DRAFTS_COUNT + SENT_COUNT + TRASH_COUNT))
}
EOF

echo "Initial counts recorded: Inbox=$INBOX_COUNT, Junk=$JUNK_COUNT"

# ============================================================
# Ensure BlueMail is running
# ============================================================
start_bluemail
wait_for_bluemail_window 60
sleep 5
maximize_bluemail
sleep 2

# Dismiss any dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="