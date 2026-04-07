#!/bin/bash
echo "=== Exporting duplicate_detection_cleanup result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather State Information
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
INITIAL_INBOX=$(cat /tmp/initial_inbox_count 2>/dev/null || echo "33")
INITIAL_TRASH=$(cat /tmp/initial_trash_count 2>/dev/null || echo "0")

# Check if BlueMail is running
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# 3. Analyze Maildir using Python
# We need to determine:
# - Current inbox count
# - Current trash count
# - Which unique subjects are remaining in Inbox?
# - Which subjects are in Trash?
# - Did the user draft the report?

python3 << 'PYEOF'
import os
import json
import email
from email.header import decode_header
import time

MAILDIR = "/home/ga/Maildir"
TASK_START = int(os.environ.get('TASK_START', 0))

def decode_str(s):
    if not s: return ""
    decoded_list = decode_header(s)
    res = ''
    for text, encoding in decoded_list:
        if isinstance(text, bytes):
            try:
                res += text.decode(encoding or 'utf-8', errors='ignore')
            except:
                res += text.decode('latin-1', errors='ignore')
        else:
            res += str(text)
    return res.strip()

def parse_email_lite(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f)
        return {
            'subject': decode_str(msg.get('Subject', '')),
            'to': decode_str(msg.get('To', '')),
            'body': str(msg.get_payload())[:1000] # simplified body extraction
        }
    except Exception:
        return {'subject': '', 'to': '', 'body': ''}

def get_subjects_in_dir(path):
    subjects = []
    if os.path.isdir(path):
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if os.path.isfile(fpath):
                data = parse_email_lite(fpath)
                subjects.append(data['subject'])
    return subjects

# Scan Inbox
inbox_subjects = []
inbox_subjects += get_subjects_in_dir(f"{MAILDIR}/cur")
inbox_subjects += get_subjects_in_dir(f"{MAILDIR}/new")

# Scan Trash
trash_subjects = []
trash_subjects += get_subjects_in_dir(f"{MAILDIR}/.Trash/cur")
trash_subjects += get_subjects_in_dir(f"{MAILDIR}/.Trash/new")

# Scan Drafts/Sent for Report
outgoing = []
for folder in ['.Drafts', '.Sent']:
    for sub in ['cur', 'new']:
        path = f"{MAILDIR}/{folder}/{sub}"
        if os.path.isdir(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                # Check timestamp if possible (files created after task start)
                if os.path.getmtime(fpath) > TASK_START:
                    outgoing.append(parse_email_lite(fpath))

# Load Ground Truths
unique_ground_truth = []
if os.path.exists('/tmp/unique_subjects.txt'):
    with open('/tmp/unique_subjects.txt', 'r') as f:
        unique_ground_truth = [l.strip() for l in f if l.strip()]

duplicated_ground_truth = []
if os.path.exists('/tmp/duplicated_subjects.txt'):
    with open('/tmp/duplicated_subjects.txt', 'r') as f:
        duplicated_ground_truth = [l.strip() for l in f if l.strip()]

result = {
    'inbox_count': len(inbox_subjects),
    'trash_count': len(trash_subjects),
    'inbox_subjects': inbox_subjects,
    'trash_subjects': trash_subjects,
    'outgoing_emails': outgoing,
    'unique_subjects_ground_truth': unique_ground_truth,
    'duplicated_subjects_ground_truth': duplicated_ground_truth,
    'bluemail_running': os.environ.get('BM_RUNNING') == 'true'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# 4. Finalize permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="