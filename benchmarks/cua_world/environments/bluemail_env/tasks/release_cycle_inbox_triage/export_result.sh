#!/bin/bash
echo "=== Exporting release_cycle_inbox_triage result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to analyze Maildir state
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
TASK_START_FILE = "/tmp/task_start_time.txt"

# Keywords for verifying flags
KEYWORDS = ["release", "patch", "bug", "version"]

def get_email_content(filepath):
    """Parse email file and return dict of headers + body."""
    try:
        with open(filepath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        subject = str(msg.get('subject', '')).lower()
        list_id = str(msg.get('list-id', '')).lower()
        
        # Get body
        body = ""
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    try:
                        body += part.get_content()
                    except:
                        pass
        else:
            try:
                body = msg.get_content()
            except:
                pass
        
        return {
            "subject": subject,
            "list_id": list_id,
            "body": body.lower(),
            "to": str(msg.get('to', '')).lower(),
            "filename": os.path.basename(filepath)
        }
    except Exception as e:
        return {"subject": "", "list_id": "", "body": "", "to": "", "filename": ""}

def count_folder(folder_name):
    """Count emails in a Maildir folder (cur + new)."""
    path = os.path.join(MAILDIR, folder_name)
    if not os.path.exists(path):
        return [], 0
    
    files = []
    for subdir in ["cur", "new"]:
        p = os.path.join(path, subdir)
        if os.path.exists(p):
            for f in os.listdir(p):
                full_path = os.path.join(p, f)
                if os.path.isfile(full_path):
                    files.append(full_path)
    return files, len(files)

# 1. Analyze Folders
dev_files, dev_count = count_folder(".Dev-High-Priority")
user_files, user_count = count_folder(".User-Community")
inbox_files, inbox_count = count_folder("cur") # Main inbox is usually root/cur and root/new
inbox_new, inbox_new_count = count_folder("new")
inbox_total = inbox_count + inbox_new_count

# 2. Analyze Sorting Accuracy
dev_correct = 0
dev_wrong = 0
for fpath in dev_files:
    data = get_email_content(fpath)
    # Check if it looks like a dev email
    if "sadev" in data['subject'] or "sadev" in data['list_id'] or "exmh" in data['subject'] or "exmh" in data['list_id']:
        dev_correct += 1
    else:
        dev_wrong += 1

user_correct = 0
user_wrong = 0
for fpath in user_files:
    data = get_email_content(fpath)
    # Check if it looks like a user/general email
    if any(x in data['subject'] or x in data['list_id'] for x in ["satalk", "ilug", "zzzzteana", "irr"]):
        user_correct += 1
    else:
        user_wrong += 1

# 3. Analyze Flagging in Dev Folder
flagged_count = 0
flagged_correctly = 0
for fpath in dev_files:
    # Dovecot stores flags in filename suffix: ...:2,S (Seen), ...:2,SF (Seen+Flagged)
    if "F" in os.path.basename(fpath).split("2,")[1]:
        flagged_count += 1
        data = get_email_content(fpath)
        # Check if it actually contained a keyword
        if any(k in data['subject'] or k in data['body'] for k in KEYWORDS):
            flagged_correctly += 1

# 4. Analyze Sent/Drafts for Report
report_found = False
reported_count = -1
report_subject_ok = False

sent_files, _ = count_folder(".Sent")
draft_files, _ = count_folder(".Drafts")
all_outgoing = sent_files + draft_files

for fpath in all_outgoing:
    data = get_email_content(fpath)
    if "council@apache.org" in data['to']:
        report_found = True
        if "release" in data['subject'] and "triage" in data['subject']:
            report_subject_ok = True
        
        # Try to extract a number from the body
        # Look for digits
        numbers = re.findall(r'\b\d+\b', data['body'])
        if numbers:
            # Take the last number found as a heuristic, or the one closest to "flagged"
            reported_count = int(numbers[0]) 

result = {
    "dev_folder_exists": os.path.isdir(os.path.join(MAILDIR, ".Dev-High-Priority")),
    "user_folder_exists": os.path.isdir(os.path.join(MAILDIR, ".User-Community")),
    "dev_count": dev_count,
    "user_count": user_count,
    "inbox_remaining": inbox_total,
    "dev_sort_correct": dev_correct,
    "dev_sort_wrong": dev_wrong,
    "user_sort_correct": user_correct,
    "user_sort_wrong": user_wrong,
    "flagged_count": flagged_count,
    "flagged_correctly_content": flagged_correctly,
    "report_found": report_found,
    "report_subject_ok": report_subject_ok,
    "reported_count": reported_count
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="