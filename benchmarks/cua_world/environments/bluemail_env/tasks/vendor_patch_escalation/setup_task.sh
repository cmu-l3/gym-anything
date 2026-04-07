#!/bin/bash
# Setup script for vendor_patch_escalation task
echo "=== Setting up vendor_patch_escalation ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# DO NOT kill BlueMail -- killing it loses the account config stored in LevelDB.
# DO NOT stop Dovecot -- it may disrupt ongoing IMAP wizard setup.
# Maildir is manipulated directly; doveadm will re-index after changes.

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear inbox and custom folders
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Load first 25 ham emails (includes SAdev patch/rule discussions and ILUG hardware issues)
TIMESTAMP=$(date +%s)
IDX=0
HAM_LOADED=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $HAM_LOADED -ge 25 ] && break
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    HAM_LOADED=$((HAM_LOADED + 1))
done
echo "Loaded ${HAM_LOADED} ham emails into inbox"

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

chown -R ga:ga "${MAILDIR}"

INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count
echo "0" > /tmp/initial_custom_folder_count

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

echo "=== Setup Complete: vendor_patch_escalation (inbox=${INBOX_COUNT}) ==="
