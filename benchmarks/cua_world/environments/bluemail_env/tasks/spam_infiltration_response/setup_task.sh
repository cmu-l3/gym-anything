#!/bin/bash
# Setup script for spam_infiltration_response task
echo "=== Setting up spam_infiltration_response ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# DO NOT kill BlueMail -- killing it loses the account config stored in LevelDB.
# DO NOT stop Dovecot -- it may disrupt ongoing IMAP wizard setup.
# Maildir is manipulated directly; doveadm will re-index after changes.

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Clear inbox
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

# Clear Junk
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true

# Remove any custom folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Clear Drafts and Sent
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

TIMESTAMP=$(date +%s)
IDX=0

# Load first 40 ham emails into inbox
HAM_LOADED=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $HAM_LOADED -ge 40 ] && break
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    HAM_LOADED=$((HAM_LOADED + 1))
done
echo "Loaded ${HAM_LOADED} ham emails into inbox"

# Move first 10 spam emails into inbox (simulating filter bypass)
SPAM_IN_INBOX=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $SPAM_IN_INBOX -ge 10 ] && break
    FNAME="${TIMESTAMP}_sp${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    SPAM_IN_INBOX=$((SPAM_IN_INBOX + 1))
done
echo "Planted ${SPAM_IN_INBOX} spam emails into inbox"

# Load remaining 10 spam emails into Junk
JUNK_LOADED=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $JUNK_LOADED -ge 10 ] && break
    fname_base=$(basename "$eml_file" .eml)
    num="${fname_base##spam_}"
    num_int=$((10#${num}))
    [ $num_int -le 10 ] && continue
    FNAME="${TIMESTAMP}_jk${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    JUNK_LOADED=$((JUNK_LOADED + 1))
done
echo "Loaded ${JUNK_LOADED} remaining spam into Junk"

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

chown -R ga:ga "${MAILDIR}"

# Record baseline state
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count

JUNK_COUNT=$(ls "${MAILDIR}/.Junk/cur/" "${MAILDIR}/.Junk/new/" 2>/dev/null | grep -c . || echo 0)
echo "${JUNK_COUNT}" > /tmp/initial_junk_count

echo "Baseline: inbox=${INBOX_COUNT} (${HAM_LOADED} ham + ${SPAM_IN_INBOX} spam), junk=${JUNK_COUNT}"

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

echo "=== Setup Complete: spam_infiltration_response ==="
