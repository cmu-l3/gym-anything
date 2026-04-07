#!/bin/bash
echo "=== Setting up meeting_followup_drafts task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Reset Maildir State
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

echo "Resetting Maildir..."

# Clear Inbox, Drafts, and any custom folders
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Remove specific task folder if it exists from previous run
rm -rf "${MAILDIR}/.Meridian-Q4" 2>/dev/null || true

# Load 50 ham emails into inbox
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded ${IDX} emails into Inbox"

# Ensure subscriptions are correct
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
# ============================================================
# 2. Record Initial State
# ============================================================
echo "${IDX}" > /tmp/initial_inbox_count
ls -1 "${MAILDIR}/.Drafts/cur/" "${MAILDIR}/.Drafts/new/" 2>/dev/null | wc -l > /tmp/initial_draft_count
date +%s > /tmp/task_start_time

# ============================================================
# 3. Prepare Application
# ============================================================
# Ensure BlueMail is running
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize window
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="