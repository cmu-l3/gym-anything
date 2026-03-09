#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python analysis to inspect Maildir state and Drafts
python3 << 'PYEOF'
import os
import json
import email
from email.policy import default
import re

MAILDIR = "/home/ga/Maildir"
VIP_FOLDER_NAME = ".VIP-Accounts" # Maildir folders usually start with dot
DRAFTS_FOLDER = ".Drafts"
GROUND_TRUTH_FILE = "/tmp/vip_ground_truth.json"

def parse_email_file(path):
    try:
        with open(path, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=default)
            sender = msg.get('From', '').strip()
            # Clean sender
            m = re.search(r'<([^>]+)>', sender)
            clean_sender = m.group(1).lower() if m else sender.lower()
            
            return {
                'sender': clean_sender,
                'subject': msg.get('Subject', '').strip(),
                'to': msg.get('To', '').strip(),
                'body': msg.get_body(preferencelist=('plain')).get_content() if msg.get_body(preferencelist=('plain')) else ""
            }
    except:
        return None

# Load Ground Truth
try:
    with open(GROUND_TRUTH_FILE, 'r') as f:
        ground_truth = json.load(f)
except:
    ground_truth = {'vip_senders': [], 'expected_emails': []}

# 1. Inspect VIP Folder content
vip_folder_path = os.path.join(MAILDIR, VIP_FOLDER_NAME)
vip_emails_found = []
vip_folder_exists = os.path.isdir(vip_folder_path)

if vip_folder_exists:
    for subdir in ['cur', 'new']:
        p = os.path.join(vip_folder_path, subdir)
        if os.path.exists(p):
            for fname in os.listdir(p):
                data = parse_email_file(os.path.join(p, fname))
                if data:
                    vip_emails_found.append(data)

# 2. Inspect Drafts/Sent for the report
drafts_path = os.path.join(MAILDIR, DRAFTS_FOLDER)
sent_path = os.path.join(MAILDIR, ".Sent")
report_candidates = []

for folder in [drafts_path, sent_path]:
    if os.path.exists(folder):
        for subdir in ['cur', 'new']:
            p = os.path.join(folder, subdir)
            if os.path.exists(p):
                for fname in os.listdir(p):
                    # Only check files modified/created recently? 
                    # For simplicity, check all, verifier checks recipient
                    data = parse_email_file(os.path.join(p, fname))
                    if data:
                        report_candidates.append(data)

# 3. Inspect Inbox (to check if items were moved OUT)
inbox_emails = []
for subdir in ['cur', 'new']:
    p = os.path.join(MAILDIR, subdir)
    if os.path.exists(p):
        for fname in os.listdir(p):
             data = parse_email_file(os.path.join(p, fname))
             if data:
                 inbox_emails.append(data)

result = {
    'ground_truth': ground_truth,
    'vip_folder_exists': vip_folder_exists,
    'vip_folder_emails': vip_emails_found,
    'inbox_emails': inbox_emails,
    'drafts_sent': report_candidates,
    'task_start': int(os.environ.get('TASK_START', 0)),
    'task_end': int(os.environ.get('TASK_END', 0))
}

with open('/tmp/task_result_data.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Prepare final result JSON
# We use a temp file and move it to handle permissions safely
mv /tmp/task_result_data.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="