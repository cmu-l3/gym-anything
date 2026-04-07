#!/bin/bash
echo "=== Setting up unsubscribe_audit task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Task configuration
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Prepare Maildir (Reset state)
echo "Resetting Maildir..."
# Remove all existing emails and custom folders
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true

# Remove custom folders (folders starting with . but not standard ones)
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# 2. Load Data (50 Ham emails from mixed lists)
echo "Loading inbox with mixed mailing list traffic..."
TIMESTAMP=$(date +%s)
IDX=0
# We load all 50 ham emails. These naturally contain mix of SAdev, ILUG, etc.
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    # Unique filename for Maildir
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
done
echo "Loaded ${IDX} emails into Inbox"

# 3. Ensure Mail Services are running
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 4. Start BlueMail
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    wait_for_bluemail_window 60
fi

# 5. UI Setup
maximize_bluemail
sleep 10 # Wait for sync

# 6. Record Initial State
# Count emails in inbox for baseline
INITIAL_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "$INITIAL_COUNT" > /tmp/initial_inbox_count
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="