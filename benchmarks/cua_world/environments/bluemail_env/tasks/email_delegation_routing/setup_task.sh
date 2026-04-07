#!/bin/bash
echo "=== Setting up email_delegation_routing task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Configuration
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Record task start time
date +%s > /tmp/task_start_timestamp

# ============================================================
# 1. Prepare Maildir
# ============================================================
echo "Preparing Maildir..."

# Clear Inbox (cur/new)
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

# Clear Sent and Drafts to ensure clean verification
rm -rf "${MAILDIR}/.Sent" 2>/dev/null || true
rm -rf "${MAILDIR}/.Drafts" 2>/dev/null || true
# Recreate them
mkdir -p "${MAILDIR}/.Sent/cur" "${MAILDIR}/.Sent/new" "${MAILDIR}/.Sent/tmp"
mkdir -p "${MAILDIR}/.Drafts/cur" "${MAILDIR}/.Drafts/new" "${MAILDIR}/.Drafts/tmp"

# Load 50 Ham emails into Inbox
# These contain the mix of Security (SAdev), Dev (exmh), and Community (ILUG) emails
echo "Loading 50 ham emails..."
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Create unique filename for Maildir
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

# Load 20 Spam emails into Junk (as distractors/background)
echo "Loading 20 spam emails into Junk..."
mkdir -p "${MAILDIR}/.Junk/cur" "${MAILDIR}/.Junk/new"
IDX=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 20 ] && break
    
    FNAME="${TIMESTAMP}_spam_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    
    IDX=$((IDX + 1))
done

# Ensure permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Record initial inbox count for "preservation" check
echo "$IDX" > /tmp/initial_inbox_count

# ============================================================
# 2. Launch Application
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
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete: 50 Inbox emails, 20 Junk emails ==="