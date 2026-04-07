#!/bin/bash
# Setup script for email_action_item_extraction task
echo "=== Setting up email_action_item_extraction ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Clean Slate: Remove existing emails and custom folders
echo "Cleaning Maildir..."
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true

# Remove any custom folders (folders starting with dot, excluding defaults)
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# 2. Load 50 real ham emails into Inbox
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0
# Ensure we have enough files
if [ -d "$ASSETS_HAM" ]; then
    for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
        [ -f "$eml_file" ] || continue
        # Limit to 50
        if [ $IDX -ge 50 ]; then break; fi
        
        # Unique filename for Maildir
        FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
        IDX=$((IDX + 1))
        TIMESTAMP=$((TIMESTAMP + 1))
    done
fi
echo "Loaded ${IDX} ham emails into inbox"

# 3. Ensure Junk has some background noise (optional, but realistic)
JUNK_IDX=0
if [ -d "/workspace/assets/emails/spam" ]; then
    for eml_file in "/workspace/assets/emails/spam"/spam_*.eml; do
        [ -f "$eml_file" ] || continue
        if [ $JUNK_IDX -ge 20 ]; then break; fi
        FNAME="${TIMESTAMP}_junk${JUNK_IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
        JUNK_IDX=$((JUNK_IDX + 1))
        TIMESTAMP=$((TIMESTAMP + 1))
    done
fi

# 4. Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

chown -R ga:ga "${MAILDIR}"

# 5. Record baseline state for verification
# Count files in cur and new
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count
echo "Initial inbox count: ${INBOX_COUNT}"

# Record start time
date +%s > /tmp/task_start_time.txt

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 7. Start BlueMail
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="