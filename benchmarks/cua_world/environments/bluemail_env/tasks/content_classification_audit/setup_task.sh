#!/bin/bash
# Setup script for content_classification_audit task
echo "=== Setting up content_classification_audit ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# DO NOT kill BlueMail -- killing it loses the account config stored in LevelDB.
# Maildir is manipulated directly; doveadm will re-index after changes.

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# ============================================================
# Clean Maildir state
# ============================================================
# Clear inbox (remove all emails from cur and new)
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

# Remove any pre-existing custom folders from previous task runs
# We keep standard folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Clear Drafts and Sent folders
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# ============================================================
# Populate Inbox with 50 HAM emails
# ============================================================
TIMESTAMP=$(date +%s)
IDX=0
# Load first 50 ham emails into inbox
# These contain a mix of security-related (SpamAssassin dev list) and general (Linux users group)
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Create unique filename format required by Dovecot/Maildir
    # Format: timestamp_uniqueid.hostname:2,flags
    # S flag = Seen (so they don't look like new unread mail, simulating existing backlog)
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded ${IDX} ham emails into inbox"
FINAL_HAM_COUNT=$IDX

# ============================================================
# Populate Junk with 20 SPAM emails (background noise)
# ============================================================
SPAM_IDX=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $SPAM_IDX -ge 20 ] && break
    
    FNAME="${TIMESTAMP}_spam${SPAM_IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    SPAM_IDX=$((SPAM_IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded ${SPAM_IDX} spam emails into Junk"

# ============================================================
# Finalize Setup
# ============================================================
# Ensure subscriptions file exists
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
# Record baseline state
echo "${FINAL_HAM_COUNT}" > /tmp/initial_inbox_count
date +%s > /tmp/task_start_time

# Ensure BlueMail is running
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize and wait for sync
maximize_bluemail
sleep 15

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete: inbox=${FINAL_HAM_COUNT}, junk=${SPAM_IDX} ==="