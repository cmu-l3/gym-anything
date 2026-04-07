#!/bin/bash
echo "=== Setting up response_template_library_setup task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Reset Maildir to clean state (Inbox populated, no custom folders)
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear existing folders/emails to ensure clean state
rm -rf "${MAILDIR}"/.* 2>/dev/null || true
rm -rf "${MAILDIR}"/* 2>/dev/null || true

# Re-create standard folders
mkdir -p "$MAILDIR/cur" "$MAILDIR/new" "$MAILDIR/tmp"
mkdir -p "$MAILDIR/.Junk/cur" "$MAILDIR/.Junk/new" "$MAILDIR/.Junk/tmp"
mkdir -p "$MAILDIR/.Drafts/cur" "$MAILDIR/.Drafts/new" "$MAILDIR/.Drafts/tmp"
mkdir -p "$MAILDIR/.Sent/cur" "$MAILDIR/.Sent/new" "$MAILDIR/.Sent/tmp"
mkdir -p "$MAILDIR/.Trash/cur" "$MAILDIR/.Trash/new" "$MAILDIR/.Trash/tmp"

# Set subscriptions
cat > "$MAILDIR/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# Populate Inbox with 50 emails
echo "Populating Inbox..."
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

chown -R ga:ga "$MAILDIR"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 2. Ensure BlueMail is running and ready
# ============================================================
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
fi

# Wait for window
wait_for_bluemail_window 60

# Maximize
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="