#!/bin/bash
echo "=== Setting up stakeholder_briefing_synthesis ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# 1. Prepare Maildir (Clear old data, Load 50 ham emails)
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Stop BlueMail if running to prevent lock issues during massive file ops
# (Though usually safe, we want a clean state)
close_bluemail

# Clear Inbox, Drafts, Sent
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Remove any custom folders from previous runs
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# Load 50 Ham emails into Inbox
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    # Stop at 50
    [ $IDX -ge 50 ] && break
    
    # Format: timestamp_idx.hostname:2,S (S=Seen)
    # We mark them as Seen so the agent isn't overwhelmed by "50 Unread" badges immediately,
    # or leave them Unread (no S flag) to simulate new work. 
    # Task desc says "unread emails", so we use ":2," (no S)
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
done
echo "Loaded ${IDX} unread emails into inbox"

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# ============================================================
# 2. Prepare Filesystem
# ============================================================
mkdir -p /home/ga/Documents
# Remove the target file if it exists
rm -f /home/ga/Documents/weekly_briefing.txt

# ============================================================
# 3. Start Application & Record State
# ============================================================
echo "Starting BlueMail..."
start_bluemail
wait_for_bluemail_window 60
maximize_bluemail
sleep 5

# Scroll to top of inbox (simulation)
xdotool key Home

# Record Start Time
date +%s > /tmp/task_start_time.txt
# Record initial Draft/Sent count
ls -1 "${MAILDIR}/.Drafts/cur/" "${MAILDIR}/.Drafts/new/" 2>/dev/null | wc -l > /tmp/initial_draft_count
ls -1 "${MAILDIR}/.Sent/cur/" "${MAILDIR}/.Sent/new/" 2>/dev/null | wc -l > /tmp/initial_sent_count

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="