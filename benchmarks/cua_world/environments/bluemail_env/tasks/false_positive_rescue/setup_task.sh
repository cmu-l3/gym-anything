#!/bin/bash
# Setup script for false_positive_rescue task
echo "=== Setting up false_positive_rescue ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Configuration
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"
GROUND_TRUTH_FILE="/tmp/false_positive_ids.txt"

# 1. Clean Slate: Clear Maildir folders
echo "Clearing existing emails..."
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Remove any custom folders from previous runs
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" | while read -r dir; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX|Archive) ;;
        *) rm -rf "$dir" ;;
    esac
done

# 2. Populate INBOX with 45 ham emails (ham_001 to ham_045)
echo "Populating Inbox..."
TIMESTAMP=$(date +%s)
IDX=0
for i in $(seq -f "%03g" 1 45); do
    eml_file="${ASSETS_HAM}/ham_${i}.eml"
    if [ -f "$eml_file" ]; then
        # Create unique filename for Maildir
        FNAME="${TIMESTAMP}_inbox_${IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
        IDX=$((IDX + 1))
    fi
done

# 3. Populate JUNK with 10 spam emails + 5 false positive ham emails
echo "Populating Junk with spam and false positives..."
rm -f "$GROUND_TRUTH_FILE"

# Add 10 Spam emails
for i in $(seq -f "%03g" 1 10); do
    eml_file="${ASSETS_SPAM}/spam_${i}.eml"
    if [ -f "$eml_file" ]; then
        FNAME="${TIMESTAMP}_spam_${i}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    fi
done

# Add 5 Ham emails (False Positives: ham_046 to ham_050)
# We extract their Message-ID to track them later for verification
for i in $(seq -f "%03g" 46 50); do
    eml_file="${ASSETS_HAM}/ham_${i}.eml"
    if [ -f "$eml_file" ]; then
        FNAME="${TIMESTAMP}_fp_${i}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
        
        # Extract Message-ID for ground truth
        MSG_ID=$(grep -i "^Message-ID:" "$eml_file" | head -1 | tr -d '\r\n')
        echo "$MSG_ID" >> "$GROUND_TRUTH_FILE"
    fi
done

# Secure the ground truth file (root only)
chmod 600 "$GROUND_TRUTH_FILE"
chown root:root "$GROUND_TRUTH_FILE"

# 4. Finalize Maildir setup
# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# 5. Record Baseline Stats for Export Script
echo "15" > /tmp/initial_junk_count
echo "45" > /tmp/initial_inbox_count
date +%s > /tmp/task_start_time.txt

# 6. Launch BlueMail
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Inbox: 45 emails"
echo "Junk: 15 emails (10 spam + 5 false positives)"