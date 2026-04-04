#!/bin/bash
echo "=== Exporting emergency_communication_prep result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final.png

# Wait a moment for any filesystem syncs
sleep 2

# Path settings
MAILDIR="/home/ga/Maildir"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_STATE_FILE="/tmp/initial_state.json"

# Python script to analyze the Maildir state and parse drafts
python3 << PYEOF
import os
import json
import re
import time

maildir = "$MAILDIR"
task_start_time = int("$TASK_START_TIME")
initial_state_path = "$INITIAL_STATE_FILE"

# Load initial state
initial_inbox_count = 50
if os.path.exists(initial_state_path):
    try:
        with open(initial_state_path, 'r') as f:
            data = json.load(f)
            initial_inbox_count = data.get('inbox_count', 50)
    except:
        pass

def count_emails_in_folder(folder_path):
    count = 0
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if os.path.exists(path):
            count += len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])
    return count

def parse_email_file(filepath):
    """Simple parser to extract To, Subject, and Body excerpt from EML file"""
    headers = {}
    body_lines = []
    in_body = False
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        lines = content.splitlines()
        for line in lines:
            if not in_body:
                if line.strip() == "":
                    in_body = True
                    continue
                # Simple header parsing
                match = re.match(r'^([\w-]+):\s*(.*)', line)
                if match:
                    key = match.group(1).lower()
                    val = match.group(2).strip()
                    # Handle multiline headers roughly if needed, but this suffices for basic checks
                    headers[key] = val
            else:
                body_lines.append(line)
                if len(body_lines) > 50: # Limit body scan
                    break
                    
        return {
            "to": headers.get("to", ""),
            "subject": headers.get("subject", ""),
            "body": "\n".join(body_lines).lower()
        }
    except Exception as e:
        return {"error": str(e)}

# 1. Analyze Folders
folders_found = {}
target_folders = ["Incident-Infrastructure", "Incident-Security", "Incident-Software"]

# Check for existence and count (handle hidden dot prefix in Maildir)
for folder_name in target_folders:
    # Maildir folders usually start with .
    # BlueMail creates them as .FolderName
    # We check case-insensitive match against directories in Maildir
    
    found = False
    count = 0
    
    for entry in os.listdir(maildir):
        if not entry.startswith('.'): continue
        
        # Remove dot
        real_name = entry[1:]
        
        # Normalize for comparison
        if real_name.replace('-', '').replace('_', '').lower() == folder_name.replace('-', '').lower():
            full_path = os.path.join(maildir, entry)
            if os.path.isdir(full_path):
                found = True
                count = count_emails_in_folder(full_path)
                folders_found[folder_name] = {"exists": True, "count": count, "actual_name": real_name}
                break
    
    if not found:
        folders_found[folder_name] = {"exists": False, "count": 0}

# 2. Analyze Inbox Delta
current_inbox_count = count_emails_in_folder(os.path.join(maildir)) # Root is inbox
inbox_reduction = initial_inbox_count - current_inbox_count

# 3. Analyze Drafts
drafts_path = os.path.join(maildir, ".Drafts")
drafts_found = []

if os.path.exists(drafts_path):
    for subdir in ['cur', 'new']:
        sp = os.path.join(drafts_path, subdir)
        if os.path.exists(sp):
            for fname in os.listdir(sp):
                fpath = os.path.join(sp, fname)
                if os.path.isfile(fpath):
                    # Check modification time for anti-gaming
                    mtime = os.path.getmtime(fpath)
                    if mtime > task_start_time:
                        parsed = parse_email_file(fpath)
                        parsed['filename'] = fname
                        parsed['mtime'] = mtime
                        drafts_found.append(parsed)

# 4. Analyze Sent (in case agent sent them instead of drafting)
sent_path = os.path.join(maildir, ".Sent")
sent_found = []

if os.path.exists(sent_path):
    for subdir in ['cur', 'new']:
        sp = os.path.join(sent_path, subdir)
        if os.path.exists(sp):
            for fname in os.listdir(sp):
                fpath = os.path.join(sp, fname)
                if os.path.isfile(fpath):
                    mtime = os.path.getmtime(fpath)
                    if mtime > task_start_time:
                        parsed = parse_email_file(fpath)
                        parsed['filename'] = fname
                        sent_found.append(parsed)

result = {
    "folders": folders_found,
    "inbox_reduction": inbox_reduction,
    "initial_inbox": initial_inbox_count,
    "current_inbox": current_inbox_count,
    "drafts": drafts_found,
    "sent_emails": sent_found,
    "task_start_time": task_start_time
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="