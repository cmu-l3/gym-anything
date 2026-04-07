#!/bin/bash
# Setup script for project_timeline_archival
echo "=== Setting up project_timeline_archival ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Environment paths
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Clean Slate: Wipe Maildir (except structure)
echo "Cleaning Maildir..."
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true

# Remove any custom folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# 2. Load Data: Mix of Exmh and Non-Exmh emails
echo "Loading email corpus..."
TIMESTAMP=$(date +%s)
IDX=0
LOADED_COUNT=0

# We need to ensure we have enough 'exmh' emails. 
# In the standard SpamAssassin corpus, 'exmh' is a common mailing list.
# We will load 50 emails total.
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    
    # Create unique filename for Maildir
    # Format: unique_id.hostname:2,S (S=Seen)
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    LOADED_COUNT=$((LOADED_COUNT + 1))
    
    [ $LOADED_COUNT -ge 50 ] && break
done

echo "Loaded $LOADED_COUNT emails into Inbox"
echo "$LOADED_COUNT" > /tmp/initial_inbox_count

# 3. Ensure folder subscriptions are default
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# 4. Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 6. Start BlueMail (preserve config, don't kill if running)
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
fi

# 7. Window Management
echo "Waiting for window..."
wait_for_bluemail_window 60
maximize_bluemail
sleep 5

# 8. Record Start State
date +%s > /tmp/task_start_time
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="