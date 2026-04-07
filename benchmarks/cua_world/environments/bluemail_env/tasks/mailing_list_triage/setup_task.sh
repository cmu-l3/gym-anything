#!/bin/bash
# Setup script for mailing_list_triage task
echo "=== Setting up mailing_list_triage ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# DO NOT kill BlueMail -- killing it loses the account config stored in LevelDB.
# DO NOT stop Dovecot -- it may disrupt ongoing IMAP wizard setup.
# Maildir is manipulated directly; doveadm will re-index after changes.

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear inbox (remove all emails from cur and new)
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

# Remove any pre-existing custom folders from previous task runs
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

# Load all 50 ham emails into inbox (cur/ with Seen flag)
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded ${IDX} ham emails into inbox"

# Reset subscriptions to defaults only
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Record baseline state
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count

JUNK_COUNT=$(ls "${MAILDIR}/.Junk/cur/" "${MAILDIR}/.Junk/new/" 2>/dev/null | grep -c . || echo 0)
echo "${JUNK_COUNT}" > /tmp/initial_junk_count

echo "0" > /tmp/initial_custom_folder_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# Ensure BlueMail is running (DO NOT kill -- preserves account config)
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize and wait for BlueMail to sync new Maildir state
maximize_bluemail
sleep 20

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete: inbox=${INBOX_COUNT} emails, task=mailing_list_triage ==="
