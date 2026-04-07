#!/bin/bash
set -e
echo "=== Setting up personalized_lead_outreach task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Clean Maildir state
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear Inbox, Sent, Drafts, Trash, Junk
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true

# Remove any custom folders (like Candidates from previous runs)
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" | while read dir; do
    dirname=$(basename "$dir")
    # Skip standard folders
    if [[ "$dirname" != ".Sent" && "$dirname" != ".Drafts" && "$dirname" != ".Trash" && "$dirname" != ".Junk" ]]; then
        rm -rf "$dir"
    fi
done

# ============================================================
# 2. Populate Inbox with real data
# ============================================================
echo "Populating inbox with ham emails..."
TIMESTAMP=$(date +%s)
IDX=0
# Load 50 ham emails
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Create unique filename for Maildir
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
done

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 3. Clean Documents
# ============================================================
rm -f /home/ga/Documents/candidates.csv 2>/dev/null || true

# ============================================================
# 4. Ensure BlueMail is running
# ============================================================
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="