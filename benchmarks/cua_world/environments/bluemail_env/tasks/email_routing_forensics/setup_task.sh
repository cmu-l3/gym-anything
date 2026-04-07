#!/bin/bash
set -e
echo "=== Setting up email_routing_forensics task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Prepare Maildir (Clear old state)
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Ensure directories exist
mkdir -p "$MAILDIR/cur" "$MAILDIR/new" "$MAILDIR/tmp"
mkdir -p "$MAILDIR/.Junk/cur" "$MAILDIR/.Junk/new" "$MAILDIR/.Junk/tmp"
mkdir -p "/home/ga/Documents"

# Clear existing emails
rm -f "$MAILDIR/cur/"* "$MAILDIR/new/"* 2>/dev/null || true
rm -f "$MAILDIR/.Junk/cur/"* "$MAILDIR/.Junk/new/"* 2>/dev/null || true

# Remove any custom folders from previous runs
find "$MAILDIR" -maxdepth 1 -type d -name ".*" | while read -r dir; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" ;;
    esac
done

# Remove previous report if exists
rm -f "/home/ga/Documents/forensic_report.txt"

# ============================================================
# 2. Load Data (Real SpamAssassin Corpus)
# ============================================================
echo "Loading emails..."
TIMESTAMP=$(date +%s)

# Load 50 Ham emails to Inbox
IDX=0
for eml_file in "$ASSETS_HAM"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    # Unique filename for Maildir
    FNAME="${TIMESTAMP}_H${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "$MAILDIR/cur/$FNAME"
    IDX=$((IDX + 1))
done

# Load 20 Spam emails to Junk
IDX=0
for eml_file in "$ASSETS_SPAM"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 20 ] && break
    FNAME="${TIMESTAMP}_S${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "$MAILDIR/.Junk/cur/$FNAME"
    IDX=$((IDX + 1))
done

# Fix permissions
chown -R ga:ga "$MAILDIR"
chown -R ga:ga "/home/ga/Documents"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 3. Start Application
# ============================================================
# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize window
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="