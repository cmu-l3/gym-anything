#!/bin/bash
echo "=== Exporting community_champion_identification result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if BlueMail is running
APP_RUNNING=$(pgrep -f "bluemail" > /dev/null && echo "true" || echo "false")

# ============================================================
# Python Script to Parse Maildir State
# ============================================================
# We need to export:
# 1. Existence of 'Champion-Candidate' folder
# 2. List of emails in that folder (specifically their From addresses)
# 3. List of emails in Drafts/Sent (To address, Subject)

python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
TARGET_FOLDER = ".Champion-Candidate"
RESULT_FILE = "/tmp/task_result.json"

def get_email_info(filepath):
    """Extract From, To, Subject from an email file."""
    try:
        with open(filepath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
            
        # Extract From address
        from_header = msg.get('From', '')
        # Extract email address from "Name <email@domain.com>"
        from_addr_match = re.search(r'<([^>]+)>', from_header)
        if from_addr_match:
            from_addr = from_addr_match.group(1)
        else:
            from_addr = from_header.strip()
            
        # Extract To address
        to_header = msg.get('To', '')
        
        return {
            'from': from_addr.lower(),
            'to': to_header.lower(),
            'subject': msg.get('Subject', ''),
            'file': os.path.basename(filepath)
        }
    except Exception as e:
        return {'error': str(e)}

def list_folder_emails(folder_name):
    """List all emails in a Maildir folder (cur + new)."""
    emails = []
    folder_path = os.path.join(MAILDIR, folder_name)
    
    if not os.path.exists(folder_path):
        return None
        
    for subdir in ['cur', 'new']:
        subpath = os.path.join(folder_path, subdir)
        if os.path.exists(subpath):
            for fname in os.listdir(subpath):
                if not fname.startswith('.'):
                    fpath = os.path.join(subpath, fname)
                    info = get_email_info(fpath)
                    emails.append(info)
    return emails

# 1. Inspect Candidate Folder
candidate_emails = list_folder_emails(TARGET_FOLDER)
folder_exists = candidate_emails is not None

# 2. Inspect Drafts and Sent
drafts = list_folder_emails(".Drafts") or []
sent = list_folder_emails(".Sent") or []
outbox = drafts + sent

# 3. Construct Result
result = {
    "task_start": int(os.environ.get('TASK_START', 0)),
    "task_end": int(os.environ.get('TASK_END', 0)),
    "app_was_running": os.environ.get('APP_RUNNING') == 'true',
    "folder_exists": folder_exists,
    "candidate_emails": candidate_emails if folder_exists else [],
    "outbox_emails": outbox,
    "screenshot_path": "/tmp/task_final.png"
}

with open(RESULT_FILE, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported data to {RESULT_FILE}")
PYEOF

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="