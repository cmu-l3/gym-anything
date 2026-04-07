#!/bin/bash
echo "=== Setting up mail_migration_dryrun task ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Directory paths
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up previous task artifacts
echo "Cleaning up previous state..."
rm -f "$DOCS_DIR/migration_manifest.csv" 2>/dev/null || true
rm -rf "$MAILDIR/cur/"* "$MAILDIR/new/"* 2>/dev/null || true
rm -rf "$MAILDIR/.Junk/cur/"* "$MAILDIR/.Junk/new/"* 2>/dev/null || true
rm -rf "$MAILDIR/.Drafts/cur/"* "$MAILDIR/.Drafts/new/"* 2>/dev/null || true
rm -rf "$MAILDIR/.Sent/cur/"* "$MAILDIR/.Sent/new/"* 2>/dev/null || true

# Remove any custom folders from previous runs
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# 2. Populate Maildir with real data
# Load 50 Ham emails into Inbox
echo "Loading inbox..."
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded ${IDX} ham emails into inbox"

# Load 20 Spam emails into Junk
echo "Loading junk..."
J_IDX=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $J_IDX -ge 20 ] && break
    FNAME="${TIMESTAMP}_junk${J_IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    J_IDX=$((J_IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded ${J_IDX} spam emails into junk"

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"
chown -R ga:ga "$DOCS_DIR"

# 3. Record Baseline State
echo "${IDX}" > /tmp/initial_inbox_count
echo "${J_IDX}" > /tmp/initial_junk_count
date +%s > /tmp/task_start_time

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# 4. Start Application
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize and Focus
maximize_bluemail
sleep 5

# 5. Capture Initial Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="