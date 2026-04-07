#!/bin/bash
echo "=== Setting up new_hire_onboarding_package task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Reset Maildir to clean state
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Clear existing contents
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true

# Remove any custom folders from previous runs
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX|Archive) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# ============================================================
# 2. Populate Inbox with 50 Ham Emails (Source Material)
# ============================================================
TIMESTAMP=$(date +%s)
IDX=0

echo "Loading 50 ham emails into inbox..."
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Unique filename for Maildir
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

# ============================================================
# 3. Populate Junk with 20 Spam Emails (Noise)
# ============================================================
SPAM_IDX=0
echo "Loading 20 spam emails into Junk..."
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $SPAM_IDX -ge 20 ] && break
    
    FNAME="${TIMESTAMP}_spam${SPAM_IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    
    SPAM_IDX=$((SPAM_IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

# Restore subscriptions
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# Set permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 4. Record Initial State & Start App
# ============================================================

# Record baseline counts
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count
date +%s > /tmp/task_start_time.txt

echo "Baseline: Inbox=${INBOX_COUNT}"

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