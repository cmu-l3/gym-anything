#!/bin/bash
echo "=== Setting up duplicate_detection_cleanup task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Configuration
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Indices of emails to duplicate (1-based to match filename numbering often used, 
# but we will iterate 0-based in logic or just pick specific files)
# We will select 25 unique emails, and duplicate 8 of them.
TOTAL_UNIQUE=25
DUPLICATE_INDICES=(2 6 10 14 18 21 23 24) # 0-based indices to duplicate

# 1. Clear existing Maildir data
echo "Clearing Maildir..."
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Trash/cur/"* "${MAILDIR}/.Trash/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# 2. Prepare Unique Emails
echo "Importing emails..."
mkdir -p /tmp/task_data
> /tmp/unique_subjects.txt
> /tmp/duplicated_subjects.txt

# We need Python to extract subjects reliably for our ground truth
cat > /tmp/extract_subject.py << 'PYEOF'
import sys
import email
from email.header import decode_header

def get_subject(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f)
        
        subject = msg.get('Subject', '')
        decoded_list = decode_header(subject)
        subject_str = ''
        for text, encoding in decoded_list:
            if isinstance(text, bytes):
                try:
                    subject_str += text.decode(encoding or 'utf-8', errors='ignore')
                except:
                    subject_str += text.decode('latin-1', errors='ignore')
            else:
                subject_str += str(text)
        return subject_str.strip()
    except Exception:
        return ""

if __name__ == "__main__":
    print(get_subject(sys.argv[1]))
PYEOF

TIMESTAMP=$(date +%s)
IDX=0

# Loop through first 25 ham emails
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge $TOTAL_UNIQUE ] && break

    # Create the Original
    # Naming convention: time_idx.host:2,S (Seen)
    FNAME_ORIG="${TIMESTAMP}_${IDX}_orig.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME_ORIG}"
    
    # Extract Subject for ground truth
    SUBJECT=$(python3 /tmp/extract_subject.py "$eml_file")
    echo "$SUBJECT" >> /tmp/unique_subjects.txt

    # Check if this index should be duplicated
    IS_DUPE=0
    for d_idx in "${DUPLICATE_INDICES[@]}"; do
        if [ "$IDX" -eq "$d_idx" ]; then
            IS_DUPE=1
            break
        fi
    done

    if [ "$IS_DUPE" -eq 1 ]; then
        # Create the Duplicate
        # Slight timestamp offset to ensure unique filename but content is identical
        # BlueMail will see same headers/Message-ID/Subject
        FNAME_DUPE="${TIMESTAMP}_${IDX}_copy.$(hostname -s):2,S"
        cp "$eml_file" "${MAILDIR}/cur/${FNAME_DUPE}"
        echo "$SUBJECT" >> /tmp/duplicated_subjects.txt
        echo "Created duplicate for: $SUBJECT"
    fi

    IDX=$((IDX + 1))
done

# 3. Load Background Spam (into Junk, just for context)
SPAM_COUNT=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $SPAM_COUNT -ge 10 ] && break
    FNAME="spam_${TIMESTAMP}_${SPAM_COUNT}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${FNAME}"
    SPAM_COUNT=$((SPAM_COUNT + 1))
done

# 4. Fix permissions
chown -R ga:ga "${MAILDIR}"
chmod 600 /tmp/unique_subjects.txt /tmp/duplicated_subjects.txt
chown root:root /tmp/unique_subjects.txt /tmp/duplicated_subjects.txt

# 5. Record Baselines
INITIAL_INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "$INITIAL_INBOX_COUNT" > /tmp/initial_inbox_count
echo "0" > /tmp/initial_trash_count
date +%s > /tmp/task_start_time

echo "Setup Summary:"
echo "  Inbox Total: $INITIAL_INBOX_COUNT"
echo "  Unique Expected: $TOTAL_UNIQUE"
echo "  Duplicates Created: ${#DUPLICATE_INDICES[@]}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 7. Start/Sync BlueMail
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize
maximize_bluemail
sleep 5

# 8. Initial Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="