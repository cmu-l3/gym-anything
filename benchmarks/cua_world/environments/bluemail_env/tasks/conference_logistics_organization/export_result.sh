#!/bin/bash
echo "=== Exporting conference_logistics_organization result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Check if BlueMail is running
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# Check count file
COUNT_FILE="/home/ga/Documents/ilug_count.txt"
COUNT_FILE_EXISTS="false"
REPORTED_COUNT="-1"

if [ -f "$COUNT_FILE" ]; then
    COUNT_FILE_EXISTS="true"
    # Extract first number found in file
    REPORTED_COUNT=$(grep -oE '[0-9]+' "$COUNT_FILE" | head -1 || echo "-1")
fi

# Python script to analyze Maildir state vs Ground Truth
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
TARGET_FOLDER_NAME = "ILUG-Events"
GROUND_TRUTH_FILE = "/tmp/task_ground_truth.json"
RESULT_JSON = "/tmp/task_result.json"

def get_emails_in_folder(folder_path):
    emails = []
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.isdir(path):
            continue
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if os.path.isfile(fpath):
                try:
                    with open(fpath, 'rb') as f:
                        msg = email.message_from_binary_file(f, policy=policy.default)
                    emails.append({
                        'subject': msg.get('subject', ''),
                        'to': msg.get('to', ''),
                        'body': str(msg.get_body(preferencelist=('plain')).get_content()) if msg.get_body(preferencelist=('plain')) else ""
                    })
                except Exception:
                    pass
    return emails

# 1. Load Ground Truth
try:
    with open(GROUND_TRUTH_FILE, 'r') as f:
        gt = json.load(f)
except:
    gt = {}

# 2. Check Folders
target_folder_path = os.path.join(MAILDIR, "." + TARGET_FOLDER_NAME)
folder_exists = os.path.isdir(target_folder_path)

# 3. Analyze content of target folder
moved_emails = get_emails_in_folder(target_folder_path) if folder_exists else []
moved_ilug_count = sum(1 for e in moved_emails if "[ILUG]" in e['subject'])
moved_non_ilug_count = len(moved_emails) - moved_ilug_count

# 4. Analyze content of Inbox (to check if any ILUG left behind)
inbox_emails = get_emails_in_folder(MAILDIR) # INBOX is root/cur + root/new
remaining_ilug_in_inbox = sum(1 for e in inbox_emails if "[ILUG]" in e['subject'])

# 5. Check Sent/Drafts for the forward
sent_emails = get_emails_in_folder(os.path.join(MAILDIR, ".Sent"))
draft_emails = get_emails_in_folder(os.path.join(MAILDIR, ".Drafts"))
all_outgoing = sent_emails + draft_emails

forward_found = False
forward_correct_subject = False
forward_correct_body = False
target_subject = gt.get('target_email', {}).get('subject', 'UNKNOWN_TARGET')

# Clean target subject for comparison (remove Re: Fwd: etc if they exist in ground truth, though usually they don't)
# We expect the forward to contain the original subject
clean_target_subj = target_subject.replace("[ILUG]", "").strip()

for mail in all_outgoing:
    # Check recipient
    if "travel-approvals@company.com" in str(mail.get('to', '')):
        forward_found = True
        
        # Check subject (should contain original subject or at least meaningful parts)
        # Loose check: "Fwd:" and some part of original subject
        subj = mail.get('subject', '')
        if clean_target_subj in subj or target_subject in subj:
            forward_correct_subject = True
            
        # Check body
        body = mail.get('body', '').lower()
        if "approve trip" in body:
            forward_correct_body = True

result = {
    "app_running": os.environ.get("APP_RUNNING") == "true",
    "folder_created": folder_exists,
    "moved_ilug_count": moved_ilug_count,
    "moved_non_ilug_count": moved_non_ilug_count,
    "remaining_ilug_in_inbox": remaining_ilug_in_inbox,
    "expected_ilug_count": gt.get("expected_ilug_count", 0),
    "reported_count_file_exists": os.environ.get("COUNT_FILE_EXISTS") == "true",
    "reported_count_value": int(os.environ.get("REPORTED_COUNT", "-1")),
    "forward_attempted": forward_found,
    "forward_correct_subject": forward_correct_subject,
    "forward_correct_body": forward_correct_body,
    "target_email_subject": target_subject
}

with open(RESULT_JSON, 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="