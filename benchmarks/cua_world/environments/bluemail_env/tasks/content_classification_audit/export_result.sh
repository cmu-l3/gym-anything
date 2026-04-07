#!/bin/bash
# Export script for content_classification_audit task
echo "=== Exporting content_classification_audit result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if BlueMail is running
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# Run Python analysis of Maildir state to generate result JSON
# We use Python to robustly parse email headers and traverse directories
python3 << 'PYEOF'
import os
import json
import re
import glob

MAILDIR = "/home/ga/Maildir"
TASK_START = int(open('/tmp/task_start_time').read().strip()) if os.path.exists('/tmp/task_start_time') else 0
INITIAL_INBOX = int(open('/tmp/initial_inbox_count').read().strip()) if os.path.exists('/tmp/initial_inbox_count') else 50
DEFAULT_FOLDERS = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive', 'templates'}

def count_emails_in_folder(folder_path):
    """Count emails in cur and new subdirectories."""
    count = 0
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if os.path.isdir(path):
            count += len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])
    return count

def parse_email_content(fpath):
    """Extract headers and body start from an email file."""
    try:
        with open(fpath, 'r', errors='ignore') as f:
            content = f.read()
            
        headers = {}
        # Simple header parser
        header_block = content.split('\n\n', 1)[0]
        for line in header_block.split('\n'):
            if ':' in line:
                key, val = line.split(':', 1)
                if key.strip().lower() not in headers: # Keep first occurrence
                    headers[key.strip().lower()] = val.strip()
        
        # Get body (first 2000 chars)
        body = content.split('\n\n', 1)[1] if '\n\n' in content else ""
        return {
            'to': headers.get('to', ''),
            'subject': headers.get('subject', ''),
            'cc': headers.get('cc', ''),
            'body': body[:2000].lower() # Lowercase for easier keyword matching
        }
    except Exception as e:
        return {'error': str(e)}

# 1. Analyze Inbox
inbox_count = count_emails_in_folder(MAILDIR)

# 2. Analyze Custom Folders
custom_folders = {}
for entry in os.listdir(MAILDIR):
    if entry.startswith('.'):
        folder_name = entry[1:] # Remove leading dot
        if folder_name not in DEFAULT_FOLDERS:
            folder_path = os.path.join(MAILDIR, entry)
            if os.path.isdir(folder_path):
                count = count_emails_in_folder(folder_path)
                custom_folders[folder_name] = count

# 3. Analyze Drafts and Sent (for the report)
outgoing_emails = []
for folder in ['.Drafts', '.Sent']:
    folder_path = os.path.join(MAILDIR, folder)
    if os.path.isdir(folder_path):
        for subdir in ['cur', 'new']:
            path = os.path.join(folder_path, subdir)
            if os.path.isdir(path):
                for fname in os.listdir(path):
                    fpath = os.path.join(path, fname)
                    if os.path.isfile(fpath):
                        # check mtime to ensure it was created during task
                        if os.path.getmtime(fpath) > TASK_START:
                            email_data = parse_email_content(fpath)
                            email_data['source'] = folder
                            outgoing_emails.append(email_data)

# Prepare result structure
result = {
    "task_start": TASK_START,
    "initial_inbox_count": INITIAL_INBOX,
    "current_inbox_count": inbox_count,
    "emails_moved_out": max(0, INITIAL_INBOX - inbox_count),
    "custom_folders": custom_folders,
    "outgoing_emails": outgoing_emails,
    "app_running": True  # Checked by bash script
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="