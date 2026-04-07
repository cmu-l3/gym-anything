#!/bin/bash
# Setup script for legal_contributor_dossier_compilation
echo "=== Setting up Legal Contributor Dossier Task ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Clean Slate: Remove all existing emails and folders
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Dossier"* 2>/dev/null || true

# Remove other custom folders to avoid confusion, keeping defaults
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

# 2. Load Dataset
# We need a mix of emails:
# - From jm@jmason.org (Target)
# - From others mentioning jm@jmason.org/Justin Mason (Mentions)
# - Irrelevant emails (Noise)
# The SpamAssassin 'ham' corpus naturally contains these as Justin Mason is the maintainer.

echo "Loading email corpus..."
TIMESTAMP=$(date +%s)
IDX=0
# Load up to 60 emails to ensure we have enough coverage
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 60 ] && break
    
    # Create unique filename for Maildir
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
done
echo "Loaded ${IDX} emails into inbox"

# 3. Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# 4. Record Start Time
date +%s > /tmp/task_start_timestamp

# 5. Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 5

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="