#!/bin/bash
echo "=== Setting up confidential_project_sorting_by_codename ==="

source /workspace/scripts/task_utils.sh

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

# Load 50 ham emails into Inbox
# We use ham emails because they contain the technical terms (SpamAssassin dev discussions)
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0
count=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    if [ -f "$eml_file" ] && [ $count -lt 50 ]; then
        # Create unique filename
        FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
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

# Force Dovecot index
doveadm index -u ga INBOX 2>/dev/null || true

# ============================================================
# Launch BlueMail
# ============================================================
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize
maximize_bluemail
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="