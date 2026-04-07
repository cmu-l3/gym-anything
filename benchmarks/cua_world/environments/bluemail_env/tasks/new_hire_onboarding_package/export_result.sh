#!/bin/bash
echo "=== Exporting new_hire_onboarding_package result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if BlueMail is running
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# Retrieve setup data
INITIAL_INBOX=$(cat /tmp/initial_inbox_count 2>/dev/null || echo "50")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use Python to analyze Maildir structure and parse emails
# This handles the complexity of Maildir headers and folder names
python3 << 'PYEOF'
import os
import json
import re
import email.parser
from email import policy

MAILDIR = "/home/ga/Maildir"
DEFAULT_FOLDERS = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive'}

def count_dir(path):
    if not os.path.isdir(path):
        return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

def parse_email_file(fpath):
    """Parse a Maildir file to extract relevant headers and body text."""
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        # Extract plain text body
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
        
        # Clean body (remove excess whitespace)
        body = re.sub(r'\s+', ' ', body).strip()

        return {
            'to': str(msg['to'] or ''),
            'cc': str(msg['cc'] or ''),
            'bcc': str(msg['bcc'] or ''),
            'subject': str(msg['subject'] or ''),
            'body': body,
            'body_word_count': len(body.split())
        }
    except Exception as e:
        return {'error': str(e), 'to': '', 'subject': '', 'body': '', 'body_word_count': 0}

# 1. Analyze Folders
custom_folders = {}
onboarding_folder_found = False
onboarding_folder_name = ""
onboarding_email_count = 0

for entry in os.listdir(MAILDIR):
    if not entry.startswith('.'):
        continue
        
    folder_name_raw = entry[1:] # Remove leading dot
    if folder_name_raw in DEFAULT_FOLDERS:
        continue
        
    full_path = os.path.join(MAILDIR, entry)
    if not os.path.isdir(full_path):
        continue
        
    # Count emails in this folder
    cnt = count_dir(os.path.join(full_path, "cur")) + count_dir(os.path.join(full_path, "new"))
    custom_folders[folder_name_raw] = cnt
    
    # Check if this looks like the onboarding folder (case-insensitive fuzzy match)
    if "onboard" in folder_name_raw.lower():
        onboarding_folder_found = True
        onboarding_folder_name = folder_name_raw
        onboarding_email_count = cnt

# 2. Analyze Inbox
inbox_count = count_dir(os.path.join(MAILDIR, "cur")) + count_dir(os.path.join(MAILDIR, "new"))

# 3. Analyze Drafts and Sent
# We check both because the agent might have sent the email (to localhost) or just saved draft
outgoing_emails = []

for folder in ['.Drafts', '.Sent']:
    for subdir in ['cur', 'new']:
        path = os.path.join(MAILDIR, folder, subdir)
        if os.path.isdir(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                if os.path.isfile(fpath):
                    parsed = parse_email_file(fpath)
                    parsed['source_folder'] = folder
                    outgoing_emails.append(parsed)

# Prepare result dict
result = {
    'bluemail_running': True, # Passed in via env var or assumed if script ran
    'inbox_count': inbox_count,
    'custom_folders': custom_folders,
    'onboarding_folder_found': onboarding_folder_found,
    'onboarding_folder_name': onboarding_folder_name,
    'onboarding_email_count': onboarding_email_count,
    'outgoing_emails': outgoing_emails,
    'timestamp': os.environ.get('TASK_END', 0)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export Summary: Onboarding Folder: {onboarding_folder_name} ({onboarding_email_count} emails), Inbox: {inbox_count}, Outgoing: {len(outgoing_emails)}")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="