#!/bin/bash
echo "=== Setting up discussion_flow_organization ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Clean Slate (Reset Maildir)
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

echo "Clearing existing emails..."
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

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

# Remove old documents
rm -f /home/ga/Documents/new_topics_digest.txt 2>/dev/null || true

# ============================================================
# 2. Populate Inbox with Real Data
# ============================================================
echo "Populating inbox with threaded conversations..."

TIMESTAMP=$(date +%s)
IDX=0
# Load 50 emails from the ham corpus
# The SpamAssassin corpus naturally contains a mix of "Re:" and new topics
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

echo "Loaded $IDX emails into Inbox"
echo "$IDX" > /tmp/initial_inbox_count

# Fix permissions
chown -R ga:ga "${MAILDIR}"
chmod -R 700 "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# ============================================================
# 3. Application Setup
# ============================================================
# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

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

echo "=== Setup Complete ==="