#!/bin/bash
echo "=== Exporting newsletter_curation_workflow result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png ga

# Run Python script to parse Maildir structures (Folders, Headers, Drafts)
# We need to extract:
# 1. Contents of 'Newsletter-Material' folder (Subjects and List-Ids)
# 2. Contents of Drafts folder (Body and Recipient)

python3 << 'PYEOF'
import os
import json
import email
from email.policy import default
import re

MAILDIR = "/home/ga/Maildir"
TARGET_FOLDER_NAME = "Newsletter-Material"

def parse_email_file(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=default)
        
        # Extract subject
        subject = msg.get('subject', '').strip()
        
        # Extract List-Id or similar headers to identify source
        list_id = msg.get('list-id', '')
        if not list_id:
            list_id = msg.get('x-mailing-list', '')
        
        # Extract body (simplistic text extraction)
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
            'subject': subject,
            'list_id': list_id,
            'to': msg.get('to', ''),
            'body': body
        }
    except Exception as e:
        return {'error': str(e)}

def get_folder_emails(folder_name_suffix):
    # Search for the folder directory (e.g., .Newsletter-Material)
    # Maildir folders usually start with '.'
    emails = []
    found_path = None
    
    # Try exact match first
    candidates = [d for d in os.listdir(MAILDIR) if d.startswith('.')]
    for d in candidates:
        # Check case-insensitive match for the suffix
        if d[1:].lower() == folder_name_suffix.lower():
            found_path = os.path.join(MAILDIR, d)
            break
    
    if found_path and os.path.isdir(found_path):
        for sub in ['cur', 'new']:
            p = os.path.join(found_path, sub)
            if os.path.isdir(p):
                for fname in os.listdir(p):
                    fpath = os.path.join(p, fname)
                    if os.path.isfile(fpath):
                        data = parse_email_file(fpath)
                        data['filename'] = fname
                        emails.append(data)
    
    return emails, found_path is not None

# 1. Get Curated Emails
curated_emails, folder_exists = get_folder_emails(TARGET_FOLDER_NAME)

# 2. Get Drafts
drafts, _ = get_folder_emails("Drafts")

# 3. Get Sent (in case they sent it instead of drafting)
sent, _ = get_folder_emails("Sent")

result = {
    "folder_exists": folder_exists,
    "curated_emails": curated_emails,
    "curated_count": len(curated_emails),
    "drafts": drafts,
    "sent": sent,
    "task_end_timestamp": os.popen("date +%s").read().strip()
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="