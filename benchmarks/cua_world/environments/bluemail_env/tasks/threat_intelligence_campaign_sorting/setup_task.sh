#!/bin/bash
# Setup script for threat_intelligence_campaign_sorting task
echo "=== Setting up Threat Intelligence Sorting Task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Configuration
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# 1. Clean existing Maildir state to ensure fresh start
echo "Cleaning Maildir..."
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Remove any custom folders from previous runs
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# 2. Populate Inbox with HAM (Distractors)
echo "Populating Inbox with distractors..."
TIMESTAMP=$(date +%s)
IDX=0
# Load 15 ham emails
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 15 ] && break
    FNAME="${TIMESTAMP}_H${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
done

# 3. Populate Junk with SPAM (The dataset for the task)
echo "Populating Junk with spam dataset..."
IDX=0
# Load 25 spam emails to ensure enough variety for both categories
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 25 ] && break
    # Unique filename
    FNAME="${TIMESTAMP}_S${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    IDX=$((IDX + 1))
done
echo "Loaded $IDX spam emails into Junk"

# 4. Fix permissions and re-index
chown -R ga:ga "${MAILDIR}"
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize window
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="