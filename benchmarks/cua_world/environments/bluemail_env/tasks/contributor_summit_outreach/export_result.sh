#!/bin/bash
# Export script for contributor_summit_outreach
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Python Script to Analyze Maildir
# We need to extract:
# - Contents of 'Summit-Candidates' folder (specifically Sender addresses)
# - Contents of 'Drafts' folder (specifically To, Bcc, Subject)
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy
from email.parser import BytesParser

MAILDIR = "/home/ga/Maildir"
TARGET_FOLDER = ".Summit-Candidates"
DRAFTS_FOLDER = ".Drafts"

def extract_addr(header_val):
    """Extract email address from header like 'Name <email@dom.com>'"""
    if not header_val:
        return ""
    # simple regex for email extraction
    match = re.search(r'<([^>]+)>', header_val)
    if match:
        return match.group(1).lower().strip()
    if '@' in header_val:
        return header_val.lower().strip()
    return ""

def parse_maildir_folder(folder_path):
    emails = []
    if not os.path.isdir(folder_path):
        return emails
        
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.isdir(path):
            continue
            
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if not os.path.isfile(fpath):
                continue
                
            try:
                with open(fpath, 'rb') as f:
                    msg = BytesParser(policy=policy.default).parse(f)
                
                # Extract headers
                sender = extract_addr(msg.get('From', ''))
                to = msg.get('To', '')
                cc = msg.get('Cc', '')
                bcc = msg.get('Bcc', '')
                subject = msg.get('Subject', '')
                
                # Sometimes BCC is in X-Bcc or implicitly stored in Drafts
                if not bcc:
                    bcc = msg.get('X-Bcc', '')

                emails.append({
                    'sender': sender,
                    'to': to,
                    'cc': cc,
                    'bcc': bcc,
                    'subject': subject,
                    'filename': fname
                })
            except Exception as e:
                print(f"Error parsing {fname}: {e}")
                continue
    return emails

# Analyze Summit-Candidates
candidates_path = os.path.join(MAILDIR, TARGET_FOLDER)
candidate_emails = parse_maildir_folder(candidates_path)

# Analyze Drafts
drafts_path = os.path.join(MAILDIR, DRAFTS_FOLDER)
draft_emails = parse_maildir_folder(drafts_path)

# Prepare Result
result = {
    "folder_exists": os.path.isdir(candidates_path),
    "candidate_count": len(candidate_emails),
    "candidates": candidate_emails,
    "draft_count": len(draft_emails),
    "drafts": draft_emails,
    "timestamp": os.popen("date +%s").read().strip()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Analysis complete: {len(candidate_emails)} candidates, {len(draft_emails)} drafts found.")
PYEOF

# 3. Secure output file
chmod 666 /tmp/task_result.json 2>/dev/null || true

# 4. Cleanup
echo "=== Export Complete ==="