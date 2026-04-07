#!/bin/bash
echo "=== Setting up newsletter_curation_workflow ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Reset Maildir to known state
# Remove all custom folders (directories starting with . but not standard ones)
echo "Cleaning old folders..."
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Clear Drafts and Sent
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# 2. Ensure Inbox has the dataset (50 ham emails)
# We re-populate to ensure timestamps/flags are clean
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true

echo "Populating inbox with mailing list data..."
TIMESTAMP=$(date +%s)
IDX=0
if [ -d "$ASSETS_HAM" ]; then
    for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
        [ -f "$eml_file" ] || continue
        # Use unique filenames
        FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
        IDX=$((IDX + 1))
    done
fi
echo "Loaded $IDX emails."

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Ensure BlueMail is running and visible
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize
maximize_bluemail
sleep 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="