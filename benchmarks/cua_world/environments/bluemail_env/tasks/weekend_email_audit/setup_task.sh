#!/bin/bash
set -e
echo "=== Setting up weekend_email_audit task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare Data
# Clear Maildir to ensure clean state
MAILDIR="/home/ga/Maildir"
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
# Remove custom folders
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" ! -name ".Drafts" ! -name ".Sent" ! -name ".Junk" ! -name ".Trash" -exec rm -rf {} +
# Clear Drafts/Sent
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true
# Remove Documents
rm -f /home/ga/Documents/weekend_audit_report.txt 2>/dev/null || true

# Load 50 ham emails
ASSETS_HAM="/workspace/assets/emails/ham"
TIMESTAMP=$(date +%s)
IDX=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    # Copy to cur with unique name
    cp "$eml_file" "${MAILDIR}/cur/${TIMESTAMP}_${IDX}.setup:2,S"
    IDX=$((IDX + 1))
done

# Fix permissions
chown -R ga:ga "${MAILDIR}"
chmod -R 700 "${MAILDIR}"

# 2. Generate Ground Truth (Hidden from Agent)
# We parse the emails currently in the inbox to determine which are Saturday (5) or Sunday (6).
python3 << 'PYEOF'
import os
import email
import email.utils
import json
import time

maildir_path = "/home/ga/Maildir/cur"
weekend_count = 0
weekend_subjects = []
total_emails = 0

for f in os.listdir(maildir_path):
    fpath = os.path.join(maildir_path, f)
    if os.path.isfile(fpath):
        total_emails += 1
        with open(fpath, 'r', errors='ignore') as fp:
            msg = email.message_from_file(fp)
            date_str = msg.get('Date')
            subject = msg.get('Subject', 'No Subject')
            if date_str:
                # Parse date
                tt = email.utils.parsedate_tz(date_str)
                if tt:
                    # mktime_tz returns UTC timestamp
                    timestamp = email.utils.mktime_tz(tt)
                    # Convert to struct_time to get wday (0=Mon, 6=Sun)
                    # We use localtime or gmtime? The RFC date includes offset.
                    # parsedate_tz parses it. mktime_tz converts to UTC epoch.
                    # We want the day of week LOCALLY to the sender? 
                    # Actually, usually "weekend" implies the date written in the header.
                    # The tuple from parsedate_tz (without the offset) contains the wday.
                    # email.utils.parsedate(date_str) returns a struct_time, indexing 6 is wday.
                    # Let's use parsedate which ignores timezone for wday calculation (uses the string)
                    pt = email.utils.parsedate(date_str)
                    if pt:
                        wday = pt[6] # 0=Mon, 6=Sun
                        if wday == 5 or wday == 6: # Sat or Sun
                            weekend_count += 1
                            weekend_subjects.append(subject)

ground_truth = {
    "total_emails": total_emails,
    "weekend_count": weekend_count,
    "weekend_subjects": weekend_subjects
}

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

print(f"Ground Truth: {weekend_count} weekend emails out of {total_emails}")
PYEOF

# Secure ground truth
chmod 600 /tmp/ground_truth.json
chown root:root /tmp/ground_truth.json

# 3. App Setup
# Record start time
date +%s > /tmp/task_start_time.txt

# Start BlueMail
if ! is_bluemail_running; then
    start_bluemail
fi
wait_for_bluemail_window 60
maximize_bluemail
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="