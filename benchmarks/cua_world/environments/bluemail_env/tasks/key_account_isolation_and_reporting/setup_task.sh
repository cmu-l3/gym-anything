#!/bin/bash
echo "=== Setting up key_account_isolation_and_reporting ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

MAILDIR="/home/ga/Maildir"
DOCS_DIR="/home/ga/Documents"
VIP_LIST_FILE="$DOCS_DIR/vip_list.txt"
GROUND_TRUTH_FILE="/tmp/vip_ground_truth.json"

mkdir -p "$DOCS_DIR"

# 1. Reset Maildir to a clean state with data
# We'll use the standard ham corpus but ensure no previous task artifacts remain
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.VIP-Accounts" 2>/dev/null || true
rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true

# Load ham emails
ASSETS_HAM="/workspace/assets/emails/ham"
echo "Populating Inbox..."
count=0
for eml in "$ASSETS_HAM"/*.eml; do
    [ -f "$eml" ] || continue
    cp "$eml" "$MAILDIR/cur/$(date +%s)_$count.ga:2,S"
    count=$((count + 1))
done

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# 2. Generate VIP List dynamically based on loaded emails
# We parse the emails to find frequent senders or just random ones
echo "Generating VIP list..."

python3 << PYEOF
import os
import re
import random
import json
import email
from email.policy import default

maildir = "$MAILDIR/cur"
vip_file = "$VIP_LIST_FILE"
ground_truth_file = "$GROUND_TRUTH_FILE"

# Parse all emails to get (sender, subject, filename)
emails = []
for f in os.listdir(maildir):
    path = os.path.join(maildir, f)
    if not os.path.isfile(path): continue
    
    with open(path, 'rb') as fp:
        try:
            msg = email.message_from_binary_file(fp, policy=default)
            sender = msg.get('From', '').strip()
            # Extract pure email address from "Name <email>"
            email_match = re.search(r'<([^>]+)>', sender)
            if email_match:
                clean_sender = email_match.group(1).lower()
            else:
                clean_sender = sender.lower()
            
            subject = msg.get('Subject', '').strip()
            if clean_sender:
                emails.append({
                    'sender': clean_sender, 
                    'raw_sender': sender,
                    'subject': subject,
                    'file': f
                })
        except Exception as e:
            continue

# Group by sender
sender_counts = {}
for e in emails:
    s = e['sender']
    sender_counts[s] = sender_counts.get(s, 0) + 1

# Select 3 senders who have at least 1 email (prefer ones with distinct subjects if possible)
unique_senders = list(sender_counts.keys())
if len(unique_senders) < 3:
    selected_senders = unique_senders
else:
    selected_senders = random.sample(unique_senders, 3)

# Write to VIP list file
with open(vip_file, 'w') as f:
    for s in selected_senders:
        f.write(s + '\n')

# Generate Ground Truth
ground_truth = {
    'vip_senders': selected_senders,
    'expected_emails': []
}

for e in emails:
    if e['sender'] in selected_senders:
        ground_truth['expected_emails'].append({
            'sender': e['sender'],
            'subject': e['subject']
        })

with open(ground_truth_file, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Selected {len(selected_senders)} VIP senders. Total target emails: {len(ground_truth['expected_emails'])}")
PYEOF

chown ga:ga "$VIP_LIST_FILE"

# 3. Start Application
if ! is_bluemail_running; then
    start_bluemail
fi

wait_for_bluemail_window 60
maximize_bluemail

# Record timestamp
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="