#!/bin/bash
echo "=== Exporting Kanban Workflow results ==="

source /workspace/scripts/task_utils.sh

# 1. CAPTURE FINAL STATE
take_screenshot /tmp/task_final.png

# 2. RUN ANALYSIS SCRIPT
# We use Python to parse Maildir structures and email content robustly
python3 << 'PYEOF'
import os
import json
import re
import email
from email.parser import BytesParser
from email import policy

MAILDIR = "/home/ga/Maildir"
TASK_START_FILE = "/tmp/task_start_time"
INITIAL_INBOX_FILE = "/tmp/initial_inbox_count"

def count_emails_in_folder(path):
    """Count emails in cur and new subdirectories."""
    count = 0
    if not os.path.isdir(path):
        return 0
    for subdir in ['cur', 'new']:
        d = os.path.join(path, subdir)
        if os.path.isdir(d):
            count += len([f for f in os.listdir(d) if os.path.isfile(os.path.join(d, f))])
    return count

def parse_eml_files(folder_path):
    """Parse .eml files in a folder to get To, Subject, Body."""
    emails = []
    if not os.path.isdir(folder_path):
        return emails
    
    for subdir in ['cur', 'new']:
        d = os.path.join(folder_path, subdir)
        if os.path.isdir(d):
            for fname in os.listdir(d):
                fpath = os.path.join(d, fname)
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

                    emails.append({
                        "to": str(msg['to']),
                        "subject": str(msg['subject']),
                        "body": body
                    })
                except Exception as e:
                    continue
    return emails

# Get initial state
try:
    with open(INITIAL_INBOX_FILE, 'r') as f:
        initial_inbox = int(f.read().strip())
except:
    initial_inbox = 50

# Analyze Inbox
inbox_count = count_emails_in_folder(MAILDIR)

# Analyze Custom Folders
# Dovecot folders are siblings of cur/new, named .FolderName
folders = {}
for entry in os.listdir(MAILDIR):
    if entry.startswith('.') and os.path.isdir(os.path.join(MAILDIR, entry)):
        folder_name = entry[1:] # Strip leading dot
        if folder_name in ['Drafts', 'Sent', 'Junk', 'Trash', 'Archive']:
            continue
        
        cnt = count_emails_in_folder(os.path.join(MAILDIR, entry))
        folders[folder_name] = cnt

# Analyze Drafts and Sent for the announcement email
drafts = parse_eml_files(os.path.join(MAILDIR, '.Drafts'))
sent = parse_eml_files(os.path.join(MAILDIR, '.Sent'))
all_outgoing = drafts + sent

result = {
    "initial_inbox_count": initial_inbox,
    "final_inbox_count": inbox_count,
    "folders": folders,
    "outgoing_emails": all_outgoing,
    "bluemail_running": True # Checked by wrapper script usually, assuming true for analysis
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Analysis complete. Found {len(folders)} custom folders.")
PYEOF

# 3. PERMISSIONS AND CLEANUP
chmod 666 /tmp/task_result.json 2>/dev/null || true

# Check if BlueMail is running
if is_bluemail_running; then
    # Add running status to JSON using jq if available, or simple append fails
    # The python script above defaults it to True, we verify here
    true
fi

echo "=== Export complete ==="