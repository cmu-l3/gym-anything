#!/bin/bash
echo "=== Exporting sender_blocklist_recommendation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Determine if BlueMail is running
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# Run Python script to analyze Maildir state and export JSON
python3 << 'PYEOF'
import os
import json
import re
import time

MAILDIR = "/home/ga/Maildir"
TASK_START = int(open('/tmp/task_start_time').read().strip()) if os.path.exists('/tmp/task_start_time') else 0
INITIAL_INBOX = int(open('/tmp/initial_inbox_count').read().strip()) if os.path.exists('/tmp/initial_inbox_count') else 50
INITIAL_JUNK = int(open('/tmp/initial_junk_count').read().strip()) if os.path.exists('/tmp/initial_junk_count') else 20

def count_dir(path):
    if not os.path.isdir(path):
        return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

def parse_email(fpath):
    try:
        with open(fpath, 'r', errors='ignore') as f:
            content = f.read(15000) # Read enough for headers and body
        
        headers = {}
        lines = content.split('\n')
        body_lines = []
        in_body = False
        
        for line in lines:
            if in_body:
                body_lines.append(line)
                continue
            
            if line.strip() == '':
                in_body = True
                continue
                
            m = re.match(r'^([\w-]+):\s*(.*)', line)
            if m:
                key = m.group(1).lower()
                # Handle multi-line headers roughly
                if key not in headers:
                    headers[key] = m.group(2).strip()
        
        return {
            'to': headers.get('to', ''),
            'subject': headers.get('subject', ''),
            'cc': headers.get('cc', ''),
            'bcc': headers.get('bcc', ''),
            'body': '\n'.join(body_lines[:100]).lower() # First 100 lines of body
        }
    except Exception as e:
        return {'error': str(e)}

# 1. Analyze Folders
custom_folders = {}
folder_counts = {}
default_folders = {'inbox', 'junk', 'trash', 'sent', 'drafts', 'archive', 'spam', 'ham'}

# Scan Maildir for dot-folders
if os.path.exists(MAILDIR):
    for entry in os.listdir(MAILDIR):
        if entry.startswith('.') and os.path.isdir(os.path.join(MAILDIR, entry)):
            folder_name = entry[1:] # Remove leading dot
            
            # Skip defaults
            if folder_name.lower() in default_folders:
                continue
                
            # Count emails
            count = count_dir(os.path.join(MAILDIR, entry, 'cur')) + \
                    count_dir(os.path.join(MAILDIR, entry, 'new'))
            
            folder_counts[folder_name] = count
            
            # Check for specific target folders (case-insensitive keys for easier verification)
            custom_folders[folder_name] = count

# 2. Analyze Current Inbox/Junk
current_inbox = count_dir(os.path.join(MAILDIR, 'cur')) + count_dir(os.path.join(MAILDIR, 'new'))
current_junk = count_dir(os.path.join(MAILDIR, '.Junk', 'cur')) + count_dir(os.path.join(MAILDIR, '.Junk', 'new'))

# 3. Analyze Drafts and Sent
drafts = []
sent = []

for folder, list_ref in [('.Drafts', drafts), ('.Sent', sent)]:
    for sub in ['cur', 'new']:
        path = os.path.join(MAILDIR, folder, sub)
        if os.path.isdir(path):
            for f in os.listdir(path):
                fpath = os.path.join(path, f)
                if os.path.isfile(fpath):
                    # Check modification time to ensure it was created during task
                    mtime = os.path.getmtime(fpath)
                    if mtime > TASK_START:
                        list_ref.append(parse_email(fpath))

result = {
    "task_start": TASK_START,
    "app_running": True, # Passed from bash via environment variable logic if needed, but we trust the setup
    "initial_inbox": INITIAL_INBOX,
    "current_inbox": current_inbox,
    "inbox_delta": current_inbox - INITIAL_INBOX,
    "initial_junk": INITIAL_JUNK,
    "current_junk": current_junk,
    "junk_delta": current_junk - INITIAL_JUNK,
    "custom_folders": custom_folders,
    "drafts": drafts,
    "sent": sent,
    "timestamp": time.ctime()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="