#!/bin/bash
# Setup script for project_inbox_zero task
echo "=== Setting up project_inbox_zero ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# DO NOT kill BlueMail -- killing it loses the account config stored in LevelDB.
# DO NOT stop Dovecot -- it may disrupt ongoing IMAP wizard setup.
# Maildir is manipulated directly; doveadm will re-index after changes.

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear inbox and ALL custom folders
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

# Create pre-existing 'Security-Discussion' folder with 5 SAdev/security emails (ham_011..ham_015)
mkdir -p "${MAILDIR}/.Security-Discussion/cur" "${MAILDIR}/.Security-Discussion/new" "${MAILDIR}/.Security-Discussion/tmp"

TIMESTAMP=$(date +%s)
IDX=100
for num in 11 12 13 14 15; do
    eml_file="${ASSETS_HAM}/ham_$(printf '%03d' $num).eml"
    [ -f "$eml_file" ] || continue
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Security-Discussion/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded 5 emails into Security-Discussion folder"

# Create pre-existing 'Hardware-Issues' folder with 5 ILUG/hardware emails (ham_016..ham_020)
mkdir -p "${MAILDIR}/.Hardware-Issues/cur" "${MAILDIR}/.Hardware-Issues/new" "${MAILDIR}/.Hardware-Issues/tmp"

for num in 16 17 18 19 20; do
    eml_file="${ASSETS_HAM}/ham_$(printf '%03d' $num).eml"
    [ -f "$eml_file" ] || continue
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Hardware-Issues/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded 5 emails into Hardware-Issues folder"

# Load remaining 40 ham emails into inbox (ham_001..ham_010, ham_021..ham_050)
HAM_LOADED=0
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    fname_base=$(basename "$eml_file" .eml)
    num="${fname_base##ham_}"
    num_int=$((10#${num}))
    # Skip ham_011 through ham_020 (already in pre-created folders)
    if [ $num_int -ge 11 ] && [ $num_int -le 20 ]; then
        continue
    fi
    [ $HAM_LOADED -ge 40 ] && break
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    HAM_LOADED=$((HAM_LOADED + 1))
done
echo "Loaded ${HAM_LOADED} ham emails into inbox"

# Reset subscriptions including pre-created folders
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
Security-Discussion
Hardware-Issues
SUBEOF

chown -R ga:ga "${MAILDIR}"

INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count
echo "2" > /tmp/initial_custom_folder_count

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

echo "=== Setup Complete: project_inbox_zero (inbox=${INBOX_COUNT}, pre_folders=2) ==="
