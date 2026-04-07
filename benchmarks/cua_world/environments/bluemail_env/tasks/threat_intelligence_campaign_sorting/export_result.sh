#!/bin/bash
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export script uses Python to parse Maildir and extract semantic content for verification
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
DEFAULT_FOLDERS = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive'}

def extract_text_content(msg):
    """Extract subject and plain text body from email object."""
    subject = msg.get('subject', '')
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == 'text/plain':
                try:
                    body += part.get_payload(decode=True).decode(part.get_content_charset() or 'utf-8', errors='ignore')
                except:
                    pass
    else:
        try:
            body = msg.get_payload(decode=True).decode(msg.get_content_charset() or 'utf-8', errors='ignore')
        except:
            pass
    return subject, body[:2000]  # Limit body size

def parse_maildir_folder(folder_path):
    """Return list of dicts {subject, body} for all emails in a folder."""
    emails = []
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path):
            continue
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if os.path.isfile(fpath):
                try:
                    with open(fpath, 'rb') as f:
                        msg = email.message_from_binary_file(f, policy=policy.default)
                        subj, body = extract_text_content(msg)
                        emails.append({
                            'subject': subj,
                            'body': body,
                            'to': msg.get('to', ''),
                            'filename': fname
                        })
                except Exception as e:
                    continue
    return emails

result = {
    'folders': {},
    'drafts': [],
    'junk_count': 0
}

# 1. Scan for custom folders and extract content
for entry in os.listdir(MAILDIR):
    if not entry.startswith('.'):
        continue
    folder_name = entry[1:] # Remove leading dot
    
    # Check Junk specifically for count
    if folder_name == 'Junk':
        junk_path = os.path.join(MAILDIR, entry)
        result['junk_count'] = len([name for name in os.listdir(os.path.join(junk_path, 'cur')) if os.path.isfile(os.path.join(junk_path, 'cur', name))])
        continue
        
    if folder_name in DEFAULT_FOLDERS:
        continue
        
    # It's a custom folder
    folder_path = os.path.join(MAILDIR, entry)
    if os.path.isdir(folder_path):
        result['folders'][folder_name] = parse_maildir_folder(folder_path)

# 2. Extract Drafts for report verification
drafts_path = os.path.join(MAILDIR, '.Drafts')
if os.path.exists(drafts_path):
    result['drafts'] = parse_maildir_folder(drafts_path)

# 3. Extract Sent items (in case they sent it instead of draft)
sent_path = os.path.join(MAILDIR, '.Sent')
if os.path.exists(sent_path):
    result['drafts'].extend(parse_maildir_folder(sent_path))

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported data for {len(result['folders'])} custom folders and {len(result['drafts'])} drafts/sent items.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="