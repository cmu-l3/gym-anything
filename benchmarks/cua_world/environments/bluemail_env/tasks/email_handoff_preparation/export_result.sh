#!/bin/bash
echo "=== Exporting email_handoff_preparation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initial baseline
INITIAL_INBOX=$(cat /tmp/initial_inbox_count 2>/dev/null || echo "50")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python analysis to inspect Maildir structure and content
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy
from email.parser import BytesParser

MAILDIR = "/home/ga/Maildir"
DEFAULT_FOLDERS = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive'}
HANDOFF_PATTERN = re.compile(r'handoff', re.IGNORECASE)

def count_dir(path):
    if not os.path.isdir(path): return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

def get_email_list_id(fpath):
    """Extract mailing list identifier from email headers."""
    try:
        with open(fpath, 'rb') as f:
            msg = BytesParser(policy=policy.default).parse(f)
        
        # Method 1: List-Id header
        list_id = msg.get('List-Id', '')
        if list_id:
            return list_id.lower()
            
        # Method 2: X-Mailing-List header
        x_list = msg.get('X-Mailing-List', '')
        if x_list:
            return x_list.lower()
            
        # Method 3: Subject prefixes like [SAdev]
        subject = msg.get('Subject', '')
        match = re.search(r'\[([\w-]+)\]', subject)
        if match:
            return match.group(1).lower()
            
        # Method 4: Return-Path domain (weak fallback)
        return 'unknown'
    except Exception:
        return 'error'

def parse_outgoing(fpath):
    """Parse a draft or sent email."""
    try:
        with open(fpath, 'rb') as f:
            msg = BytesParser(policy=policy.default).parse(f)
        
        body = ""
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    body += part.get_content()
        else:
            body = msg.get_content()
            
        return {
            'to': msg.get('To', ''),
            'subject': msg.get('Subject', ''),
            'body_snippet': body[:5000]  # First 5000 chars for analysis
        }
    except Exception:
        return {'to': '', 'subject': '', 'body_snippet': ''}

# 1. Analyze Inbox
inbox_count = count_dir(f"{MAILDIR}/cur") + count_dir(f"{MAILDIR}/new")

# 2. Find Handoff Folder
handoff_folder_data = {
    'exists': False,
    'name': '',
    'count': 0,
    'lists_found': [],
    'distinct_list_count': 0
}

candidate_folders = []
for entry in os.listdir(MAILDIR):
    if not entry.startswith('.'): continue
    folder_name = entry[1:] # Remove dot
    if folder_name in DEFAULT_FOLDERS: continue
    
    # Check if this folder is a handoff folder
    if HANDOFF_PATTERN.search(folder_name):
        folder_path = os.path.join(MAILDIR, entry)
        if os.path.isdir(folder_path):
            count = count_dir(f"{folder_path}/cur") + count_dir(f"{folder_path}/new")
            
            # Analyze contents for diversity
            lists = set()
            for subdir in ['cur', 'new']:
                dpath = os.path.join(folder_path, subdir)
                if os.path.isdir(dpath):
                    for fname in os.listdir(dpath):
                        fpath = os.path.join(dpath, fname)
                        if os.path.isfile(fpath):
                            lid = get_email_list_id(fpath)
                            if lid not in ['unknown', 'error']:
                                lists.add(lid)
            
            candidate_folders.append({
                'name': folder_name,
                'count': count,
                'lists': list(lists)
            })

# Select best candidate (highest count)
if candidate_folders:
    best = max(candidate_folders, key=lambda x: x['count'])
    handoff_folder_data['exists'] = True
    handoff_folder_data['name'] = best['name']
    handoff_folder_data['count'] = best['count']
    handoff_folder_data['lists_found'] = best['lists']
    handoff_folder_data['distinct_list_count'] = len(best['lists'])

# 3. Analyze Drafts/Sent for Briefing
outgoing_emails = []
for folder in ['.Drafts', '.Sent']:
    for subdir in ['cur', 'new']:
        dpath = f"{MAILDIR}/{folder}/{subdir}"
        if os.path.isdir(dpath):
            # Sort by time, get recent ones
            files = sorted([os.path.join(dpath, f) for f in os.listdir(dpath) if os.path.isfile(os.path.join(dpath, f))], key=os.path.getmtime)
            # Filter for recent
            for fpath in files:
                if os.path.getmtime(fpath) > float(os.environ.get('TASK_START_TIME', 0)):
                    outgoing_emails.append(parse_outgoing(fpath))

result = {
    'inbox_count': inbox_count,
    'handoff_folder': handoff_folder_data,
    'outgoing_emails': outgoing_emails
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json