#!/bin/bash
echo "=== Setting up community_influencer_scout task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Reset Maildir to a clean state with specific data
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear existing mail
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Scout-ILUG" 2>/dev/null || true
rm -rf "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "/home/ga/Documents/ilug_candidates.csv" 2>/dev/null || true

# Ensure documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Load Ham emails (SpamAssassin corpus contains ILUG emails)
# We want a mix of ILUG and non-ILUG, and a mix of Re: and non-Re:
echo "Loading email corpus..."
TIMESTAMP=$(date +%s)
IDX=0

# Load up to 60 emails to ensure we get a good mix
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 60 ] && break
    
    # Create unique filename with 'Seen' flag (S)
    # Format: unique_id:2,S
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

echo "Loaded ${IDX} emails into Inbox"

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 2. Record Initial State
# ============================================================
# Count ILUG emails for baseline (grep case insensitive)
ILUG_COUNT=$(grep -l -i "ilug" "${MAILDIR}/cur/"* 2>/dev/null | wc -l)
echo "$ILUG_COUNT" > /tmp/initial_ilug_count
echo "Baseline: $ILUG_COUNT ILUG-related emails in corpus"

date +%s > /tmp/task_start_time

# ============================================================
# 3. App Setup
# ============================================================
# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize window
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="