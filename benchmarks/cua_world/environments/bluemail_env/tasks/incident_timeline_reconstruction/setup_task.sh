#!/bin/bash
echo "=== Setting up Incident Timeline Reconstruction Task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Configuration
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
SUBJECTS_FILE="/tmp/corpus_subjects.txt"

# 1. Clean Maildir state
echo "Cleaning Maildir..."
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true
# Remove custom folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done
# Clear Drafts/Sent
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# 2. Load 50 Ham Emails
echo "Loading corpus emails..."
TIMESTAMP=$(date +%s)
IDX=0
rm -f "$SUBJECTS_FILE"

# Extract subjects while copying
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    
    # Copy to Inbox
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    # Extract Subject for verification reference
    # Use python for reliable header parsing
    python3 -c "import email.policy, email.parser, sys; msg = email.parser.BytesParser(policy=email.policy.default).parse(open('$eml_file', 'rb')); print(msg['subject'])" >> "$SUBJECTS_FILE" 2>/dev/null || true

    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

echo "Loaded $IDX emails. Subjects saved to $SUBJECTS_FILE"

# 3. Reset Subscriptions
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"
chmod 644 "$SUBJECTS_FILE"

# 4. Record Initial State
echo "$IDX" > /tmp/initial_inbox_count
date +%s > /tmp/task_start_time

# 5. Start/Restart BlueMail
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Ensure window is ready
maximize_bluemail
sleep 5

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="