#!/bin/bash
echo "=== Setting up Kanban Workflow Setup task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Directory definitions
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# 1. CLEANUP
# Remove existing custom folders to ensure clean state
echo "Cleaning up existing folders..."
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Clear Inbox, Drafts, Sent
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# 2. LOAD DATA
# Load 50 ham emails into Inbox
echo "Loading inbox..."
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    # Unique filename for Maildir format
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded $IDX emails into Inbox"

# Load 20 spam emails into Junk (baseline noise)
echo "Loading junk..."
JUNK_IDX=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $JUNK_IDX -ge 20 ] && break
    FNAME="${TIMESTAMP}_junk${JUNK_IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    JUNK_IDX=$((JUNK_IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# 3. RECORD INITIAL STATE
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Record baseline counts
ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . > /tmp/initial_inbox_count || echo "0" > /tmp/initial_inbox_count
date +%s > /tmp/task_start_time

# 4. START/RESET APP
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