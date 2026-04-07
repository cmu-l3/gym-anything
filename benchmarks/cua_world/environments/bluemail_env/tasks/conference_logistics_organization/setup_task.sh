#!/bin/bash
set -e
echo "=== Setting up conference_logistics_organization ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Clean Slate Setup
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear existing mail
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
rm -f "/home/ga/Documents/ilug_count.txt" 2>/dev/null || true

# Remove custom folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# ============================================================
# 2. Data Loading & Ground Truth Generation
# ============================================================
# We need to mix [ILUG] emails with others and identify the winner (most recent ILUG)
echo "Selecting and loading emails..."

python3 << 'PYEOF'
import os
import shutil
import email
from email import policy
import glob
import json
from datetime import datetime
import time

assets_dir = "/workspace/assets/emails/ham"
maildir_cur = "/home/ga/Maildir/cur"
ground_truth_file = "/tmp/task_ground_truth.json"

# Get all ham files
files = glob.glob(os.path.join(assets_dir, "*.eml"))
files.sort()

loaded_count = 0
ilug_count = 0
most_recent_ilug = None
most_recent_date = None

# We want a mix: ensure we get ILUG emails and non-ILUG emails
# Iterate through files, load max 40 total
for i, fpath in enumerate(files):
    if loaded_count >= 40:
        break
        
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
            
        subject = msg.get('subject', '')
        date_header = msg.get('date')
        
        # Parse date for comparison
        parsed_date = email.utils.parsedate_to_datetime(date_header) if date_header else datetime.min
        
        is_ilug = "[ILUG]" in subject
        
        # Copy file to Maildir with unique name
        # Format: timestamp_idx.hostname:2,S (S=Seen)
        timestamp = int(time.time())
        dest_name = f"{timestamp}_{i}.host:2,S"
        shutil.copy(fpath, os.path.join(maildir_cur, dest_name))
        
        loaded_count += 1
        
        if is_ilug:
            ilug_count += 1
            # Check if this is the most recent
            if most_recent_ilug is None or (parsed_date and parsed_date > most_recent_date):
                most_recent_date = parsed_date
                most_recent_ilug = {
                    "subject": subject,
                    "date": date_header,
                    "filename": os.path.basename(fpath)
                }

    except Exception as e:
        print(f"Skipping {fpath}: {e}")

# Save ground truth
gt = {
    "total_loaded": loaded_count,
    "expected_ilug_count": ilug_count,
    "target_email": most_recent_ilug
}

with open(ground_truth_file, 'w') as f:
    json.dump(gt, f, indent=2)

print(f"Loaded {loaded_count} emails ({ilug_count} ILUG tags).")
print(f"Target email: {most_recent_ilug['subject'] if most_recent_ilug else 'None'}")
PYEOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"
chown ga:ga "/tmp/task_ground_truth.json"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 3. Application Launch
# ============================================================
# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize
maximize_bluemail
sleep 5

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="