#!/bin/bash
echo "=== Setting up release_cycle_inbox_triage task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Reset Maildir to known state
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear existing contents
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true

# Remove custom folders from previous runs
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Load 50 ham emails
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Mark as Seen (:2,S) so they aren't all bold/unread, reducing visual noise
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
done

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 2. Ensure BlueMail is running
# ============================================================
if ! is_bluemail_running; then
    start_bluemail
    # Allow extra time for first start/sync
    wait_for_bluemail_window 60
fi

# Maximize window
maximize_bluemail
sleep 5

# ============================================================
# 3. Capture Initial State
# ============================================================
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="