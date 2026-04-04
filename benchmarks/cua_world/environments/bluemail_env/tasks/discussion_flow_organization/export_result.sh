#!/bin/bash
echo "=== Exporting discussion_flow_organization results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check BlueMail status
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# ============================================================
# Python Analysis of Maildir and Files
# ============================================================
# We use Python to parse email headers reliably to verify sorting accuracy
python3 << 'PYEOF'
import os
import json
import re
import email.header
from email.parser import Parser

MAILDIR = "/home/ga/Maildir"
DIGEST_PATH = "/home/ga/Documents/new_topics_digest.txt"
TASK_START = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

def decode_subject(header_val):
    if not header_val:
        return ""
    try:
        parts = email.header.decode_header(header_val)
        subject = ""
        for part, encoding in parts:
            if isinstance(part, bytes):
                try:
                    subject += part.decode(encoding or 'utf-8', errors='ignore')
                except:
                    subject += part.decode('latin-1', errors='ignore')
            else:
                subject += part
        return subject
    except Exception:
        return str(header_val)

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
                    with open(fpath, 'r', errors='ignore') as f:
                        msg = Parser().parse(f)
                    
                    subj = decode_subject(msg['subject'])
                    to = msg['to'] or ""
                    
                    emails.append({
                        'subject': subj,
                        'to': to,
                        'filename': fname
                    })
                except Exception:
                    continue
    return emails

# 1. Analyze Folders
folders_data = {}
target_folders = ['New-Topics', 'Ongoing-Discussions', 'INBOX']
folder_map = {
    'New-Topics': os.path.join(MAILDIR, '.New-Topics'),
    'Ongoing-Discussions': os.path.join(MAILDIR, '.Ongoing-Discussions'),
    'INBOX': MAILDIR
}

for name, path in folder_map.items():
    if name == 'INBOX':
        # INBOX is special in Maildir (root)
        emails = get_emails_in_folder(path)
    elif os.path.isdir(path):
        emails = get_emails_in_folder(path)
    else:
        emails = []
    
    folders_data[name] = {
        'exists': os.path.isdir(path) or name == 'INBOX',
        'count': len(emails),
        'subjects': [e['subject'] for e in emails]
    }

# 2. Analyze Digest File
digest_exists = False
digest_content = ""
digest_created_in_task = False

if os.path.exists(DIGEST_PATH):
    digest_exists = True
    mtime = os.path.getmtime(DIGEST_PATH)
    if mtime > TASK_START:
        digest_created_in_task = True
    try:
        with open(DIGEST_PATH, 'r', errors='ignore') as f:
            digest_content = f.read()
    except:
        digest_content = ""

# 3. Analyze Drafts for Triage Email
drafts = get_emails_in_folder(os.path.join(MAILDIR, '.Drafts'))
sent = get_emails_in_folder(os.path.join(MAILDIR, '.Sent'))
all_outgoing = drafts + sent

triage_email_found = False
for email_data in all_outgoing:
    if 'triage-team@company.com' in email_data.get('to', '').lower():
        triage_email_found = True
        break

# Prepare Result
result = {
    "folders": folders_data,
    "digest": {
        "exists": digest_exists,
        "created_in_task": digest_created_in_task,
        "content": digest_content
    },
    "triage_email_found": triage_email_found,
    "inbox_count_final": folders_data['INBOX']['count']
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Add Bash-level checks
APP_RUNNING=$(pgrep -f "bluemail" > /dev/null && echo "true" || echo "false")

# Append/Merge checks if Python script failed (failsafe)
if [ ! -f /tmp/task_result.json ]; then
    echo "Python export failed, writing fallback..."
    echo "{\"error\": \"Export failed\"}" > /tmp/task_result.json
fi

# Add screenshots path and app status
jq --arg app "$APP_RUNNING" --arg ss "/tmp/task_final.png" \
   '. + {app_running: $app, screenshot_path: $ss}' \
   /tmp/task_result.json > /tmp/task_result.tmp && mv /tmp/task_result.tmp /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="