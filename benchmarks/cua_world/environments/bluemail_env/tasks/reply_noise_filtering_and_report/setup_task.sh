#!/bin/bash
echo "=== Setting up reply_noise_filtering_and_report ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Directory definitions
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# 1. Reset Maildir to clean state
echo "Cleaning Maildir..."
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* "${MAILDIR}/tmp/"*
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"*
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"*
rm -rf "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"*

# Remove any custom folders from previous runs
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" | while read dir; do
    dirname=$(basename "$dir")
    if [[ "$dirname" != ".Drafts" && "$dirname" != ".Sent" && "$dirname" != ".Junk" && "$dirname" != ".Trash" ]]; then
        rm -rf "$dir"
    fi
done

# 2. Prepare Data: Load emails and ensure a mix of "Re:" and non-"Re:"
# We use Python to copy and optionally modify subjects to ensure the task is well-defined
echo "Populating Inbox..."
python3 << 'PYEOF'
import os
import shutil
import glob
import email
from email import policy
from email.parser import BytesParser

src_dir = "/workspace/assets/emails/ham"
dst_dir = "/home/ga/Maildir/cur"
os.makedirs(dst_dir, exist_ok=True)

files = sorted(glob.glob(os.path.join(src_dir, "*.eml")))[:50]
timestamp = 1700000000

# We want roughly 50-50 split for the task to be interesting
for i, fpath in enumerate(files):
    with open(fpath, 'rb') as f:
        msg = BytesParser(policy=policy.default).parse(f)
    
    original_subject = msg['subject'] or ""
    
    # Force "Re:" on even indices if not present, strip it from odd indices
    if i % 2 == 0:
        if not original_subject.lower().strip().startswith('re:'):
            del msg['subject']
            msg['subject'] = 'Re: ' + original_subject
    else:
        # Make sure "new topics" don't start with Re:
        clean_subj = original_subject
        while clean_subj.lower().strip().startswith('re:'):
             clean_subj = clean_subj[3:].strip()
        if clean_subj != original_subject:
             del msg['subject']
             msg['subject'] = clean_subj
    
    # Save to Maildir
    # Filename format: unique_time.id.host:2,S (S=Seen, no F flag initially)
    out_name = f"{timestamp + i}_{i}.host:2,S"
    out_path = os.path.join(dst_dir, out_name)
    
    with open(out_path, 'wb') as out:
        out.write(msg.as_bytes())

print(f"Processed {len(files)} emails into Inbox")
PYEOF

# 3. Force re-indexing
chown -R ga:ga "${MAILDIR}"
# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 4. Calculate Ground Truth (for reference/debugging, though verifier calculates fresh)
# Count how many have "Re:" and how many don't
RE_COUNT=$(grep -ri "^Subject:.*Re:" "${MAILDIR}/cur" | wc -l)
TOTAL_COUNT=$(ls "${MAILDIR}/cur" | wc -l)
echo "Ground Truth: Total=$TOTAL_COUNT, Re_Count=$RE_COUNT" > /tmp/task_ground_truth

# 5. Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 5

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

date +%s > /tmp/task_start_time
echo "=== Setup complete ==="