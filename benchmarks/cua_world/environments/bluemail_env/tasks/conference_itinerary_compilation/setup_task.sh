#!/bin/bash
set -e
echo "=== Setting up Conference Itinerary Compilation Task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Reset Maildir to known state
# Remove all emails from inbox/cur and inbox/new
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

# Remove any custom folders (directories starting with . followed by name, except defaults)
# Default folders in Dovecot Maildir usually start with . (e.g. .Sent, .Trash)
# We want to remove any .Dublin-Events or similar from previous runs
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" | while read dir; do
    base=$(basename "$dir")
    case "$base" in
        .Drafts|.Sent|.Junk|.Trash|.INBOX|.spam|.ham|.Archive|.) ;;
        *) rm -rf "$dir" ;;
    esac
done

# Clear Sent and Drafts to ensure clean verification
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true

# 2. Populate Inbox with real data (ILUG corpus contains social events)
echo "Populating inbox..."
TIMESTAMP=$(date +%s)
IDX=0
# Load 50 ham emails. The ILUG corpus is rich in "beer", "pub", "meetup" content.
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    # Unique filename for Maildir
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    [ $IDX -ge 60 ] && break # Cap at 60 emails
done

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 3. Ensure BlueMail is running and clean
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window
wait_for_bluemail_window 60

# Maximize
maximize_bluemail
sleep 5

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="