#!/bin/bash
set -e
echo "=== Setting up ticket_system_submission task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Prepare Maildir State
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Ensure clean slate for specific folders used in this task
rm -rf "${MAILDIR}/.Processed-Tickets" 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true

# Ensure inbox has data (reload if empty to be safe)
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
if [ "$INBOX_COUNT" -lt 10 ]; then
    echo "Inbox low, reloading ham emails..."
    rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
    TIMESTAMP=$(date +%s)
    IDX=0
    for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
        [ -f "$eml_file" ] || continue
        FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
        IDX=$((IDX + 1))
        TIMESTAMP=$((TIMESTAMP + 1))
    done
fi

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Record initial counts
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "$INBOX_COUNT" > /tmp/initial_inbox_count

# ============================================================
# Application Setup
# ============================================================
# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window
wait_for_bluemail_window 60

# Maximize
sleep 2
maximize_bluemail

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="