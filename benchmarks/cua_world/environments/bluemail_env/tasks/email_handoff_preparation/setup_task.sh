#!/bin/bash
echo "=== Setting up email_handoff_preparation ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Prepare Maildir (Clear old state)
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Clear standard folders
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true

# Remove any custom folders from previous runs
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# ============================================================
# 2. Load Real Data (SpamAssassin Corpus)
# ============================================================
TIMESTAMP=$(date +%s)
IDX=0

# Load 50 HAM emails into Inbox
# These contain the mailing list traffic (SAdev, ILUG, etc.)
echo "Loading 50 ham emails into Inbox..."
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Format: timestamp_idx.hostname:2,S (S=Seen/Read)
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
done

# Load 20 SPAM emails into Junk (Background noise)
JUNK_IDX=0
echo "Loading 20 spam emails into Junk..."
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $JUNK_IDX -ge 20 ] && break
    
    FNAME="${TIMESTAMP}_junk${JUNK_IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    JUNK_IDX=$((JUNK_IDX + 1))
done

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# ============================================================
# 3. Record Baseline State
# ============================================================
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count
date +%s > /tmp/task_start_time.txt

echo "Baseline recorded: $INBOX_COUNT emails in Inbox"

# ============================================================
# 4. App Setup
# ============================================================
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
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

echo "=== Setup Complete ==="