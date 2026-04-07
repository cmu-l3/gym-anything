#!/bin/bash
set -e
echo "=== Setting up Executive Inbox Bankruptcy Task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Clean Slate: Clear all Maildir content
echo "Cleaning Maildir..."
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* "${MAILDIR}/tmp/"*
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"*
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"*
rm -rf "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"*
rm -rf "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"*

# Remove any custom folders (directories starting with . followed by name, excluding defaults)
find "$MAILDIR" -maxdepth 1 -type d -name ".*" | while read -r dir; do
    dirname=$(basename "$dir")
    case "$dirname" in
        .Drafts|.Sent|.Junk|.Trash|.INBOX|.) continue ;;
        *) rm -rf "$dir" ;;
    esac
done

# 2. Populate Inbox with 50 emails
# We add a small delay or explicit timestamp increment to ensure robust date ordering
echo "Populating Inbox with 50 emails..."
TIMESTAMP=$(date +%s)
COUNT=0
for eml in "$ASSETS_HAM"/*.eml; do
    if [ "$COUNT" -ge 50 ]; then break; fi
    
    # Create unique filename with sequential timestamp to ensure predictable order
    # Format: unique_id:2, (flags)
    # We use S (Seen) flag so they aren't all marked 'New' which might distract
    DEST_NAME="${TIMESTAMP}_${COUNT}.$(hostname):2,S"
    cp "$eml" "${MAILDIR}/cur/${DEST_NAME}"
    
    # Increment timestamp for the next file so "most recent" is chemically pure
    TIMESTAMP=$((TIMESTAMP + 60))
    COUNT=$((COUNT + 1))
done

# 3. Reset Subscriptions
echo "Junk\nDrafts\nSent\nTrash" > "${MAILDIR}/subscriptions"

# 4. Re-index for Dovecot
chown -R ga:ga "$MAILDIR"
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 5. Launch BlueMail
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 5

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

# 7. Record Task Start
date +%s > /tmp/task_start_time.txt
echo "$COUNT" > /tmp/initial_inbox_count.txt

echo "=== Setup Complete: Loaded $COUNT emails ==="