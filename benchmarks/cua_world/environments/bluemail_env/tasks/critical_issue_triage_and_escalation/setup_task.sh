#!/bin/bash
# Setup script for critical_issue_triage_and_escalation task
echo "=== Setting up critical_issue_triage_and_escalation ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Clean up Maildir
# Remove all emails from cur and new
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

# Remove any custom folders
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

# 2. Load Data (Prioritize "Critical" emails to ensure task is solvable)
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0

# First, find and copy up to 10 emails containing "critical" keywords
# grep -l returns filenames. We limit to 10.
CRITICAL_FILES=$(grep -lE "panic|fatal|fail|error" "${ASSETS_HAM}"/*.eml | head -n 10)

for eml_file in $CRITICAL_FILES; do
    if [ -f "$eml_file" ]; then
        FNAME="${TIMESTAMP}_crit${IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
        IDX=$((IDX + 1))
        TIMESTAMP=$((TIMESTAMP + 1))
    fi
done
echo "Loaded ${IDX} critical emails"

# Fill the rest with general ham up to 50 total
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ $IDX -ge 50 ] && break
    # Skip if we already loaded it (simple check by filename might fail if grep returned full paths,
    # but exact duplication isn't fatal in Maildir, just redundant. 
    # To be cleaner, we just check if we have enough.)
    
    FNAME="${TIMESTAMP}_gen${IDX}.$(hostname -s):2,S"
    # Copy blindly; duplicates are acceptable 'noise'
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Total loaded emails: ${IDX}"

# 3. Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

chown -R ga:ga "${MAILDIR}"

# 4. Record Baseline & Timestamp
date +%s > /tmp/task_start_timestamp
echo "${IDX}" > /tmp/initial_inbox_count

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# 5. Launch BlueMail
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 15

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="