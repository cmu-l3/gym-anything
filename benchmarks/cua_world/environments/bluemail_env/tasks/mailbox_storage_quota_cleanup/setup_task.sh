#!/bin/bash
# Setup script for mailbox_storage_quota_cleanup task
echo "=== Setting up mailbox_storage_quota_cleanup ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Configuration
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# ============================================================
# 1. Clean Slate
# ============================================================
echo "Cleaning Maildir..."
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
# Remove custom folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# ============================================================
# 2. Populate Normal Emails (Correspondence)
# ============================================================
echo "Populating normal emails..."
TIMESTAMP=$(date +%s)
IDX=0
HAM_COUNT=0
# Load ~45 normal emails
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $HAM_COUNT -ge 45 ] && break
    
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    HAM_COUNT=$((HAM_COUNT + 1))
done
echo "Loaded ${HAM_COUNT} normal emails."

# ============================================================
# 3. Inject Large Asset Emails
# ============================================================
echo "Injecting large asset emails..."

# Function to create a large dummy email
create_large_email() {
    local subject="$1"
    local filename="${TIMESTAMP}_large${IDX}.$(hostname -s):2,S"
    local size_mb=5
    local output_path="${MAILDIR}/cur/${filename}"

    # Header
    cat > "$output_path" << EOF
Return-Path: <backup@internal.org>
Delivered-To: ga@example.com
Received: from localhost (localhost [127.0.0.1])
	by $(hostname) (Postfix) with ESMTP id 12345
	for <ga@example.com>; $(date -R)
From: "System Backup" <backup@internal.org>
To: ga@example.com
Subject: ${subject}
Date: $(date -R)
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

This is a large asset file backup. 
Please verify integrity before deletion.
[Binary Data Below]
EOF

    # Append random data to make it ~5MB
    # Using dd from /dev/urandom is slow, let's use /dev/zero with tr for speed but non-zero chars
    # actually, purely random isn't needed, just size.
    # We'll generate a 5MB block of alphanumeric data to avoid binary issues in some viewers, though maildir handles binary fine.
    # Using base64 from /dev/urandom is safer for email clients.
    head -c 4M /dev/urandom | base64 >> "$output_path"

    echo "Created large email: $subject ($output_path)"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
}

LARGE_SUBJECTS=(
    "Project Assets Backup 1"
    "Project Assets Backup 2"
    "High Res Dump"
    "Video Archive"
    "Log Dump 2023"
)

for subj in "${LARGE_SUBJECTS[@]}"; do
    create_large_email "$subj"
done

# ============================================================
# 4. Populate Trash (Pre-existing small items)
# ============================================================
echo "Populating Trash..."
# Copy 3 random spam emails to Trash
TRASH_COUNT=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $TRASH_COUNT -ge 3 ] && break
    
    FNAME="${TIMESTAMP}_trash${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Trash/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    TRASH_COUNT=$((TRASH_COUNT + 1))
done
echo "Loaded ${TRASH_COUNT} items into Trash."

# ============================================================
# 5. Finalize Setup
# ============================================================
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Record initial stats
INITIAL_SIZE=$(du -sb "${MAILDIR}" | cut -f1)
echo "$INITIAL_SIZE" > /tmp/initial_maildir_size_bytes
echo "$HAM_COUNT" > /tmp/initial_ham_count
date +%s > /tmp/task_start_time

echo "Initial Maildir size: $(($INITIAL_SIZE / 1024 / 1024)) MB"

# Start BlueMail
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize
maximize_bluemail
sleep 5

# Screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="