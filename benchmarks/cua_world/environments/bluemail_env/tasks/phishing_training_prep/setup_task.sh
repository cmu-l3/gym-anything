#!/bin/bash
# Setup script for phishing_training_prep task
echo "=== Setting up phishing_training_prep ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Directory paths
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Record task start time
date +%s > /tmp/task_start_timestamp

# ============================================================
# 1. Prepare Maildir (Clean State)
# ============================================================
echo "Cleaning Maildir..."
# Remove emails from Inbox
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true

# Remove any custom folders (keep standard ones)
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Clear Junk, Drafts, Sent
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# ============================================================
# 2. Load Data (Real Ham and Spam)
# ============================================================
TIMESTAMP=$(date +%s)
HOSTNAME=$(hostname -s)

# Load 50 Ham emails into Inbox
echo "Loading 50 Ham emails into Inbox..."
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    # Target filename format: unique_id:2,S (S=Seen)
    TARGET="${MAILDIR}/cur/${TIMESTAMP}_ham_${IDX}.${HOSTNAME}:2,S"
    cp "$eml_file" "$TARGET"
    IDX=$((IDX + 1))
done
echo "Loaded $IDX ham emails."

# Load 20 Spam emails into Junk
echo "Loading 20 Spam emails into Junk..."
IDX=0
# Ensure Junk directory exists
mkdir -p "${MAILDIR}/.Junk/cur" "${MAILDIR}/.Junk/new" "${MAILDIR}/.Junk/tmp"

for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 20 ] && break
    TARGET="${MAILDIR}/.Junk/cur/${TIMESTAMP}_spam_${IDX}.${HOSTNAME}:2,"
    # Note: No 'S' flag, so they appear unread
    cp "$eml_file" "$TARGET"
    IDX=$((IDX + 1))
done
echo "Loaded $IDX spam emails."

# Reset subscriptions file
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Save baseline for verification
echo "$IDX" > /tmp/initial_junk_count

# ============================================================
# 3. Start BlueMail
# ============================================================
echo "Starting BlueMail..."
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 15  # Allow sync

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="