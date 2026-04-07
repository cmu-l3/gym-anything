#!/bin/bash
echo "=== Setting up confidential_project_sorting_by_codename ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Prepare Maildir
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear existing Maildir data (keep structure, remove content)
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true

# Remove any existing custom folders
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" | while read dir; do
    dirname=$(basename "$dir")
    # Keep default folders
    if [[ "$dirname" != ".Drafts" && "$dirname" != ".Sent" && "$dirname" != ".Trash" && "$dirname" != ".Junk" ]]; then
        rm -rf "$dir"
    fi
done

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# Load 50 ham emails into Inbox.
# Seed them into Maildir/new so BlueMail sees them as newly arrived mail even
# when the account was already configured during post_start and the app is open.
# In the cached flow, copying straight into cur/:2,S can leave BlueMail showing
# an empty/stale inbox until the client is manually restarted.
# We use ham emails because they contain the technical terms (SpamAssassin dev discussions)
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0
count=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    if [ -f "$eml_file" ] && [ $count -lt 50 ]; then
        # Create unique filename
        FNAME="${TIMESTAMP}_${IDX}.$(hostname -s)"
        cp "$eml_file" "${MAILDIR}/new/${FNAME}"
        IDX=$((IDX + 1))
        count=$((count + 1))
    fi
done
echo "Loaded $count emails into Inbox"

# Record initial counts
echo "$count" > /tmp/initial_inbox_count
echo "0" > /tmp/initial_project_folders_count

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# ============================================================
# Launch BlueMail
# ============================================================
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize
maximize_bluemail
# Give BlueMail extra time to pick up the newly seeded Maildir/new messages.
sleep 20

# Capture initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="
