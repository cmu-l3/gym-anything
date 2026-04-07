#!/bin/bash
echo "=== Setting up Support Ticket Acknowledgment Workflow ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Reset Maildir State
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Ensure directories exist
mkdir -p "$MAILDIR/cur" "$MAILDIR/new" "$MAILDIR/.Sent/cur" "$MAILDIR/.Sent/new"

# Remove target folder if it exists from previous run
rm -rf "$MAILDIR/.Tickets-Created" 2>/dev/null || true

# Clear Sent folder to make verification easy (we only want to see new replies)
rm -f "$MAILDIR/.Sent/cur/"* "$MAILDIR/.Sent/new/"* 2>/dev/null || true

# Clear Inbox
rm -f "$MAILDIR/cur/"* "$MAILDIR/new/"* 2>/dev/null || true

# Load fresh ham emails (50 count)
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    # Add unique prefix to ensure sort order is deterministic based on filename if needed
    # :2,S means "Seen" - we'll mark them as seen so the agent doesn't get distracted by bold text
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

# Fix permissions
chown -R ga:ga "$MAILDIR"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 2. App Setup
# ============================================================
echo "Starting BlueMail..."

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
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