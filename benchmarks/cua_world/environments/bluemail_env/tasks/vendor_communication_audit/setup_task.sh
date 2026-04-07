#!/bin/bash
echo "=== Setting up Vendor Communication Audit ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Clean previous state
# Remove specific audit folder if exists from previous run
rm -rf "${MAILDIR}/.Audit-SourceForge" 2>/dev/null || true

# Clear Inbox to ensure consistent starting state
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true

# Clear Drafts
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true

# 2. Populate Inbox with real data
# We need to ensure a good mix of SourceForge and non-SourceForge emails.
# The SpamAssassin easy_ham corpus contains many emails from lists hosted on sourceforge.
echo "Populating inbox with email corpus..."

TIMESTAMP=$(date +%s)
IDX=0
# Load first 60 emails from ham corpus (usually contains plenty of SF traffic)
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 60 ] && break
    
    # Create unique filename for Maildir
    # Format: unique_name:2,flags (S=Seen)
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done

echo "Loaded $IDX emails into Inbox."

# 3. Ensure folder subscription file is clean
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# 4. Fix permissions
chown -R ga:ga "${MAILDIR}"

# 5. Record Baseline
# Count how many sourceforge emails are actually in the inbox to establish ground truth
# We grep case-insensitive for sourceforge.net
SF_COUNT=$(grep -ri "sourceforge.net" "${MAILDIR}/cur" | cut -d: -f1 | sort | uniq | wc -l)
echo "$SF_COUNT" > /tmp/baseline_sf_count
echo "Baseline SourceForge emails in inbox: $SF_COUNT"

# Record start time
date +%s > /tmp/task_start_time.txt

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 7. Start BlueMail
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize
maximize_bluemail
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="