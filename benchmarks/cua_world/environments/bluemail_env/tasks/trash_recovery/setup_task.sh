#!/bin/bash
# Setup script for trash_recovery task
echo "=== Setting up trash_recovery ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Ensure Dovecot is running for IMAP
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true

# 1. Clean existing Maildir state
echo "Cleaning Maildir..."
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Remove custom folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# 2. Identify target emails for "Accidental Deletion" scenario
# We need emails from 'exmh-workers' or 'ILUG' lists to put in Trash.
echo "Preparing dataset..."
mkdir -p /tmp/dataset_prep
TARGET_FILES="/tmp/dataset_prep/targets.txt"
OTHER_FILES="/tmp/dataset_prep/others.txt"
> "$TARGET_FILES"
> "$OTHER_FILES"

# Scan assets
for eml in "${ASSETS_HAM}"/*.eml; do
    [ -f "$eml" ] || continue
    # Check headers for list identifiers
    if grep -qiE "^(List-Id|X-Mailing-List|Subject):.*(exmh-workers|ilug)" "$eml"; then
        echo "$eml" >> "$TARGET_FILES"
    else
        echo "$eml" >> "$OTHER_FILES"
    fi
done

TARGET_COUNT=$(wc -l < "$TARGET_FILES")
echo "Found $TARGET_COUNT target emails (exmh-workers/ILUG)"

# 3. Populate Trash
# Move ALL targets to Trash (scenario: user bulk deleted them)
# Fill the rest of Trash to reach 15 total using 'other' emails
TRASH_TARGET=15
CURRENT_TRASH=0
TIMESTAMP=$(date +%s)
IDX=0

# Move targets to Trash
while IFS= read -r eml_file; do
    FNAME="${TIMESTAMP}_trash${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Trash/cur/${FNAME}"
    IDX=$((IDX + 1))
    CURRENT_TRASH=$((CURRENT_TRASH + 1))
done < "$TARGET_FILES"

# Fill remainder of Trash
NEEDED=$((TRASH_TARGET - CURRENT_TRASH))
if [ $NEEDED -gt 0 ]; then
    head -n $NEEDED "$OTHER_FILES" | while IFS= read -r eml_file; do
        FNAME="${TIMESTAMP}_trash${IDX}.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/.Trash/cur/${FNAME}"
        IDX=$((IDX + 1))
        CURRENT_TRASH=$((CURRENT_TRASH + 1))
    done
    # Remove used 'other' files from list so we don't put duplicates in Inbox
    sed -i "1,${NEEDED}d" "$OTHER_FILES"
fi

echo "Populated Trash with $CURRENT_TRASH emails ($TARGET_COUNT targets)"

# 4. Populate Inbox with remaining 'other' emails (~35)
INBOX_LIMIT=35
CURRENT_INBOX=0
while IFS= read -r eml_file; do
    [ $CURRENT_INBOX -ge $INBOX_LIMIT ] && break
    FNAME="${TIMESTAMP}_inbox${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    CURRENT_INBOX=$((CURRENT_INBOX + 1))
done < "$OTHER_FILES"

echo "Populated Inbox with $CURRENT_INBOX emails"

# 5. Populate Junk (Background noise)
JUNK_LIMIT=20
J_IDX=0
for eml in "${ASSETS_SPAM}"/*.eml; do
    [ $J_IDX -ge $JUNK_LIMIT ] && break
    FNAME="${TIMESTAMP}_junk${J_IDX}.$(hostname -s):2,S"
    cp "$eml" "${MAILDIR}/.Junk/cur/${FNAME}"
    J_IDX=$((J_IDX + 1))
done

# 6. Set permissions and re-index
chown -R ga:ga "${MAILDIR}"
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# 7. Record Ground Truth
echo "$CURRENT_INBOX" > /tmp/initial_inbox_count
echo "$CURRENT_TRASH" > /tmp/initial_trash_count
echo "$TARGET_COUNT" > /tmp/target_trash_count
date +%s > /tmp/task_start_time

# 8. Launch BlueMail
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 15  # Allow sync

# 9. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Trash contains $CURRENT_TRASH emails ($TARGET_COUNT to recover)"
echo "Inbox contains $CURRENT_INBOX emails"