#!/bin/bash
echo "=== Setting up emergency_communication_prep task ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Reset Maildir to known clean state
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

echo "Resetting Maildir..."

# Clear standard folders
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true

# Remove any custom folders from previous runs (especially the ones we want the agent to create)
rm -rf "${MAILDIR}/.Incident-Infrastructure" 2>/dev/null || true
rm -rf "${MAILDIR}/.Incident-Security" 2>/dev/null || true
rm -rf "${MAILDIR}/.Incident-Software" 2>/dev/null || true
# Clean up any other stray folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# ============================================================
# 2. Populate Inbox and Junk with Real Data
# ============================================================
TIMESTAMP=$(date +%s)
IDX=0

# Load 50 Ham emails into Inbox
if [ -d "$ASSETS_HAM" ]; then
    for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
        [ -f "$eml_file" ] || continue
        # Copy to cur/ with 'Seen' flag (,S) so they don't look like new unread mail
        FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
        IDX=$((IDX + 1))
        TIMESTAMP=$((TIMESTAMP + 1))
        [ $IDX -ge 50 ] && break
    done
    echo "Loaded $IDX ham emails into Inbox"
fi

# Load 20 Spam emails into Junk
SPAM_IDX=0
if [ -d "$ASSETS_SPAM" ]; then
    for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
        [ -f "$eml_file" ] || continue
        FNAME="${TIMESTAMP}_spam${SPAM_IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
        SPAM_IDX=$((SPAM_IDX + 1))
        TIMESTAMP=$((TIMESTAMP + 1))
        [ $SPAM_IDX -ge 20 ] && break
    done
    echo "Loaded $SPAM_IDX spam emails into Junk"
fi

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# ============================================================
# 3. Force Re-indexing
# ============================================================
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# ============================================================
# 4. Record Initial State & Timestamps
# ============================================================
# Record start time for anti-gaming (drafts must be created AFTER this)
date +%s > /tmp/task_start_time.txt

# Record initial counts
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "{\"inbox_count\": $INBOX_COUNT, \"junk_count\": $SPAM_IDX}" > /tmp/initial_state.json

# ============================================================
# 5. Launch Application
# ============================================================
echo "Ensuring BlueMail is running..."
if ! is_bluemail_running; then
    start_bluemail
    # Allow longer wait for first launch
    wait_for_bluemail_window 60
fi

# Maximize window
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="