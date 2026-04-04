#!/bin/bash
# Export script for critical_issue_triage_and_escalation task
echo "=== Exporting results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Run Python analysis
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"

def parse_email_file(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
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
            'subject': msg.get('subject', '').strip(),
            'to': msg.get('to', '').strip(),
            'from': msg.get('from', '').strip(),
            'body': body.lower()[:5000] # truncate for safety
        }
    except Exception as e:
        return {'subject': 'error', 'body': str(e)}

def get_folder_emails(folder_path):
    emails = []
    for subdir in ['cur', 'new']:
        dpath = os.path.join(folder_path, subdir)
        if os.path.isdir(dpath):
            for fname in os.listdir(dpath):
                if fname.startswith('.'): continue
                fpath = os.path.join(dpath, fname)
                if os.path.isfile(fpath):
                    emails.append(parse_email_file(fpath))
    return emails

# 1. Analyze Triage-Critical Folder
triage_folder_name = "Triage-Critical"
triage_path = f"{MAILDIR}/.{triage_folder_name}"
triage_emails = []
triage_folder_exists = os.path.isdir(triage_path)

if triage_folder_exists:
    triage_emails = get_folder_emails(triage_path)

# 2. Analyze Sent Folder
sent_path = f"{MAILDIR}/.Sent"
sent_emails = []
if os.path.isdir(sent_path):
    sent_emails = get_folder_emails(sent_path)

result = {
    'triage_folder_exists': triage_folder_exists,
    'triage_email_count': len(triage_emails),
    'triage_emails': triage_emails,
    'sent_emails': sent_emails,
    'sent_count': len(sent_emails)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported: Triage Exists={triage_folder_exists}, Count={len(triage_emails)}, Sent={len(sent_emails)}")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="