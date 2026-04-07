#!/bin/bash
echo "=== Setting up sender_blocklist_recommendation task ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Clean and Prepare Maildir
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

echo "Resetting Maildir..."
# Clear Inbox, Junk, Drafts, Sent
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Remove custom folders from previous runs
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" | while read dir; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" ;;
    esac
done

# Ensure folder structure exists
mkdir -p "${MAILDIR}/cur" "${MAILDIR}/new" "${MAILDIR}/tmp"
mkdir -p "${MAILDIR}/.Junk/cur" "${MAILDIR}/.Junk/new" "${MAILDIR}/.Junk/tmp"
mkdir -p "${MAILDIR}/.Drafts/cur" "${MAILDIR}/.Drafts/new" "${MAILDIR}/.Drafts/tmp"
mkdir -p "${MAILDIR}/.Sent/cur" "${MAILDIR}/.Sent/new" "${MAILDIR}/.Sent/tmp"
mkdir -p "${MAILDIR}/.Trash/cur" "${MAILDIR}/.Trash/new" "${MAILDIR}/.Trash/tmp"

# Set subscriptions
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# Use timestamp for unique filenames
TIMESTAMP=$(date +%s)
IDX=0

# Load 50 Ham emails into Inbox
HAM_COUNT=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $HAM_COUNT -ge 50 ] && break
    FNAME="${TIMESTAMP}_h${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    HAM_COUNT=$((HAM_COUNT + 1))
done
echo "Loaded ${HAM_COUNT} ham emails into Inbox"

# Load 20 Spam emails into Junk
SPAM_COUNT=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $SPAM_COUNT -ge 20 ] && break
    FNAME="${TIMESTAMP}_s${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    SPAM_COUNT=$((SPAM_COUNT + 1))
done
echo "Loaded ${SPAM_COUNT} spam emails into Junk"

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# ============================================================
# 2. Record Baseline State
# ============================================================
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count

JUNK_COUNT=$(ls "${MAILDIR}/.Junk/cur/" "${MAILDIR}/.Junk/new/" 2>/dev/null | grep -c . || echo 0)
echo "${JUNK_COUNT}" > /tmp/initial_junk_count

date +%s > /tmp/task_start_time

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# ============================================================
# 3. Launch Application
# ============================================================
echo "Ensuring BlueMail is running..."
if ! is_bluemail_running; then
    start_bluemail
    # Wait longer for first launch to ensure DB sync
    wait_for_bluemail_window 60
fi

# Maximize window
sleep 5
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Inbox: $INBOX_COUNT"
echo "Junk: $JUNK_COUNT"