#!/bin/bash
set -e
echo "=== Setting up post_vacation_inbox_cleanup task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# ============================================================
# Configure Maildir State
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Ensure Dovecot is running for IMAP access
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true

# 1. Reset Inbox: Clear and load 50 ham emails
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
echo "Cleared inbox"

TIMESTAMP=$(date +%s)
IDX=0
# Load 50 ham emails
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Format: timestamp.id.host:2,S (S=Seen, no F flag)
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
done
echo "Loaded $IDX ham emails into Inbox"
echo "$IDX" > /tmp/initial_inbox_count

# 2. Reset Junk: Load 20 spam emails (just to have a realistic messy state)
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
SPAM_IDX=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $SPAM_IDX -ge 20 ] && break
    
    FNAME="${TIMESTAMP}_spam${SPAM_IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    SPAM_IDX=$((SPAM_IDX + 1))
done
echo "Loaded $SPAM_IDX spam emails into Junk"

# 3. Clear Trash, Drafts, Sent
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
echo "0" > /tmp/initial_trash_count
echo "0" > /tmp/initial_flagged_count

# 4. Remove any existing Archive folders
rm -rf "${MAILDIR}/.Archive" "${MAILDIR}/.Archives" "${MAILDIR}/.archive" 2>/dev/null || true

# 5. Fix permissions and re-index
chown -R ga:ga "${MAILDIR}"
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# Application Setup
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
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="