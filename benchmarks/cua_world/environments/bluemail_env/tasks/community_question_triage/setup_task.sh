#!/bin/bash
echo "=== Setting up community_question_triage ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Reset Maildir to known state
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear all current emails and custom folders
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
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

# ============================================================
# 2. Populate Inbox with specific mix of Real Data
# ============================================================
# We need a mix of:
# - Replies (Subject: Re: ...)
# - New Topics (No Re:)
# - Questions (Subject contains ?)
#
# We use real emails but modify headers slightly if needed to ensure
# we have enough examples of each case for robust verification.
# However, the prompt prefers REAL data. The SpamAssassin corpus
# naturally has a mix. We will load 60 random emails.
# ============================================================

echo "Populating inbox..."
TIMESTAMP=$(date +%s)
IDX=0
COUNT=0
TARGET_COUNT=60

for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $COUNT -ge $TARGET_COUNT ] && break
    
    # Copy to Maildir with unique name
    # Suffix :2,S means "Seen" (read)
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    COUNT=$((COUNT + 1))
done

echo "Loaded $COUNT emails into Inbox."

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 3. Application Setup
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

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="