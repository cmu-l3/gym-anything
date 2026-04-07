#!/bin/bash
set -e
echo "=== Setting up Chronological Archive Organization task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Environment Setup & Cleaning
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clear existing email data to ensure clean state
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* "${MAILDIR}/tmp/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Remove any existing custom folders
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" | while read -r dir; do
    folder=$(basename "$dir")
    case "$folder" in
        .Drafts|.Sent|.Junk|.Trash|.INBOX|.) continue ;;
        *) rm -rf "$dir" ;;
    esac
done

# ============================================================
# 2. Load Data & Generate Ground Truth
# ============================================================
echo "Loading emails and generating ground truth..."

# We use python to copy emails and simultaneously record their dates
# This ensures we know exactly what distribution to expect
python3 << 'PYEOF'
import os
import shutil
import glob
import email.utils
from email import message_from_file
import json
import time
import socket

source_dir = "/workspace/assets/emails/ham"
dest_dir = "/home/ga/Maildir/cur"
hostname = socket.gethostname()

# Ensure destination exists
os.makedirs(dest_dir, exist_ok=True)

# Select 50 emails
files = sorted(glob.glob(os.path.join(source_dir, "*.eml")))[:50]
distribution = {}
email_metadata = {}

timestamp = int(time.time())

for i, src in enumerate(files):
    try:
        with open(src, 'r', encoding='latin1') as f:
            msg = message_from_file(f)
        
        date_str = msg.get('Date')
        if not date_str:
            continue
            
        # Parse date to YYYY-MM
        dt = email.utils.parsedate_to_datetime(date_str)
        if not dt:
            continue
            
        key = f"{dt.year}-{dt.month:02d}"
        
        # Update distribution counts
        distribution[key] = distribution.get(key, 0) + 1
        
        # Copy file to Maildir with unique name
        unique_name = f"{timestamp}_{i}.{hostname}:2,S"
        dst = os.path.join(dest_dir, unique_name)
        shutil.copy2(src, dst)
        
        # Record expected mapping
        email_metadata[unique_name] = key
        
    except Exception as e:
        print(f"Skipping {src}: {e}")

# Save ground truth
with open('/tmp/ground_truth_distribution.json', 'w') as f:
    json.dump({
        'counts': distribution,
        'mapping': email_metadata,
        'total_loaded': len(email_metadata)
    }, f, indent=2)

print(f"Loaded {len(email_metadata)} emails.")
print("Date distribution:", json.dumps(distribution, indent=2))
PYEOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 3. Application Setup
# ============================================================

# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
    # Wait for window
    wait_for_bluemail_window 60
fi

# Maximize window
maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="