#!/bin/bash
# Export script for trash_recovery task
echo "=== Exporting trash_recovery result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check BlueMail status
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# 3. Analyze Maildir with Python
# We need to verify:
# - Recovered-Critical folder exists
# - It contains emails
# - Those emails are the correct ones (match exmh-workers or ILUG)
# - Trash count decreased
# - Inbox count stable (didn't just move everything to inbox)
# - Draft/Sent email exists

python3 << 'PYEOF'
import os
import json
import re

MAILDIR = "/home/ga/Maildir"
DEFAULT_FOLDERS = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive'}

def count_dir(path):
    if not os.path.isdir(path):
        return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

def parse_email(fpath):
    try:
        with open(fpath, 'r', errors='ignore') as f:
            content = f.read(15000) # Read enough for headers + some body
        
        headers = {}
        body_start = 0
        lines = content.split('\n')
        
        # Simple header parser
        for i, line in enumerate(lines):
            if line.strip() == "":
                body_start = i + 1
                break
            # Handle folded headers
            if line.startswith((' ', '\t')) and i > 0:
                # Append to last header
                last_key = list(headers.keys())[-1]
                headers[last_key] += " " + line.strip()
            else:
                parts = line.split(':', 1)
                if len(parts) == 2:
                    headers[parts[0].lower()] = parts[1].strip()
        
        body = "\n".join(lines[body_start:body_start+50])
        
        return {
            'to': headers.get('to', ''),
            'subject': headers.get('subject', ''),
            'list_id': headers.get('list-id', ''),
            'x_mailing_list': headers.get('x-mailing-list', ''),
            'from': headers.get('from', ''),
            'body': body.lower()
        }
    except Exception as e:
        return {'error': str(e)}

# Current Counts
inbox_count = count_dir(f"{MAILDIR}/cur") + count_dir(f"{MAILDIR}/new")
trash_count = count_dir(f"{MAILDIR}/.Trash/cur") + count_dir(f"{MAILDIR}/.Trash/new")

# Find Custom Folders
custom_folders = {}
recovery_folder_info = {
    "exists": False,
    "name": None,
    "count": 0,
    "target_emails_found": 0
}

target_pattern = re.compile(r'(exmh-workers|ilug)', re.IGNORECASE)

for entry in os.listdir(MAILDIR):
    if not entry.startswith('.'): continue
    folder_name = entry[1:]
    if folder_name in DEFAULT_FOLDERS: continue
    
    path = os.path.join(MAILDIR, entry)
    if not os.path.isdir(path): continue
    
    # Count emails
    files = []
    for subdir in ['cur', 'new']:
        sp = os.path.join(path, subdir)
        if os.path.isdir(sp):
            files.extend([os.path.join(sp, f) for f in os.listdir(sp) if os.path.isfile(os.path.join(sp, f))])
    
    count = len(files)
    custom_folders[folder_name] = count
    
    # Check if this is likely the recovery folder
    if 'recover' in folder_name.lower():
        recovery_folder_info['exists'] = True
        recovery_folder_info['name'] = folder_name
        recovery_folder_info['count'] = count
        
        # Check content of emails in this folder
        matches = 0
        for fpath in files:
            eml = parse_email(fpath)
            # Check for target list indicators
            search_text = (eml.get('list_id', '') + " " + 
                           eml.get('x_mailing_list', '') + " " + 
                           eml.get('subject', '') + " " + 
                           eml.get('from', ''))
            if target_pattern.search(search_text):
                matches += 1
        recovery_folder_info['target_emails_found'] = matches

# Parse Drafts/Sent
outgoing = []
for folder in ['.Drafts', '.Sent']:
    for subdir in ['cur', 'new']:
        path = os.path.join(MAILDIR, folder, subdir)
        if os.path.isdir(path):
            for f in os.listdir(path):
                if os.path.isfile(os.path.join(path, f)):
                    outgoing.append(parse_email(os.path.join(path, f)))

# Read initial states
try:
    with open('/tmp/initial_trash_count', 'r') as f:
        initial_trash = int(f.read().strip())
except:
    initial_trash = 15

try:
    with open('/tmp/initial_inbox_count', 'r') as f:
        initial_inbox = int(f.read().strip())
except:
    initial_inbox = 35

result = {
    "initial_trash": initial_trash,
    "current_trash": trash_count,
    "initial_inbox": initial_inbox,
    "current_inbox": inbox_count,
    "custom_folders": custom_folders,
    "recovery_folder": recovery_folder_info,
    "outgoing_emails": outgoing,
    "bluemail_running": os.path.exists("/proc/1/comm") # Placeholder check
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Add BlueMail running status from bash
BM_RUNNING_BOOL="false"
[ "$BM_RUNNING" = "true" ] && BM_RUNNING_BOOL="true"

# Update json with proper running status
jq --argjson running $BM_RUNNING_BOOL '.bluemail_running = $running' /tmp/task_result.json > /tmp/task_result.tmp && mv /tmp/task_result.tmp /tmp/task_result.json

cat /tmp/task_result.json
echo "=== Export Complete ==="