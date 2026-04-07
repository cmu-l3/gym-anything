#!/bin/bash
echo "=== Setting up multi_client_inbox_partitioning task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Clean Maildir state
# Remove all emails from inbox
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

# Remove any existing custom folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Clear Drafts and Sent
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# 2. Populate Inbox with 50 Ham emails
# All marked as READ (Seen) to start with, so the agent has to explicitly mark ILUG as unread.
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    # :2,S means v2 format, Seen (Read)
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded ${IDX} ham emails into inbox (Read state)"

# 3. Reset Subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 4. Ensure BlueMail is running
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize window
maximize_bluemail
sleep 5

# Record task start time
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="