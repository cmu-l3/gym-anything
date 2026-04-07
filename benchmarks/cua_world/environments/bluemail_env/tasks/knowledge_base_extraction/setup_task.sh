#!/bin/bash
echo "=== Setting up Knowledge Base Extraction Task ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Configuration
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up previous state
echo "Cleaning previous data..."
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${DOCS_DIR}/kb_index.txt" 2>/dev/null || true

# Remove any existing KB folders from previous runs
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" | while read dir; do
    dirname=$(basename "$dir" | sed 's/^\.//')
    case "$dirname" in
        Drafts|Sent|Junk|Trash|INBOX|Archive) ;;
        *) 
            echo "Removing old folder: $dirname"
            rm -rf "$dir" 
            ;;
    esac
done

# 2. Populate Inbox with 50 real technical emails (Ham)
echo "Populating Inbox..."
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Unique filename for Maildir
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded $IDX ham emails."

# 3. Populate Junk with 20 spam emails (Background noise)
echo "Populating Junk..."
SPAM_IDX=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $SPAM_IDX -ge 20 ] && break
    
    FNAME="${TIMESTAMP}_spam${SPAM_IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    
    SPAM_IDX=$((SPAM_IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

# 4. Set permissions
chown -R ga:ga "${MAILDIR}"
chown -R ga:ga "${DOCS_DIR}"

# 5. Record baseline state
echo "$IDX" > /tmp/initial_inbox_count
date +%s > /tmp/task_start_time

# 6. Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# 7. Ensure BlueMail is running and ready
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
fi

# Wait for window and maximize
wait_for_bluemail_window 60
sleep 5
maximize_bluemail
sleep 2

# Take initial screenshot
take_screenshot /tmp/kb_task_start.png

echo "=== Setup Complete ==="
echo "Inbox: $IDX emails"
echo "Junk: $SPAM_IDX emails"