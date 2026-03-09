#!/bin/bash
echo "=== Exporting stakeholder_briefing_synthesis result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# Python Script to Parse Emails and File Content
# ============================================================
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy
from email.parser import BytesParser

MAILDIR = "/home/ga/Maildir"
BRIEFING_FILE = "/home/ga/Documents/weekly_briefing.txt"
TASK_START = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

def parse_maildir_folder(folder_path):
    """Parses all emails in cur/ and new/ of a maildir folder."""
    emails = []
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.isdir(path):
            continue
        
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if not os.path.isfile(fpath):
                continue
            
            # Check modification time to see if created during task
            mtime = os.path.getmtime(fpath)
            created_during_task = mtime > TASK_START
            
            try:
                with open(fpath, 'rb') as f:
                    msg = BytesParser(policy=policy.default).parse(f)
                
                # Extract body
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
                    "body": str(body)[:5000],  # Truncate large bodies
                    "created_during_task": created_during_task,
                    "filename": fname
                })
            except Exception as e:
                print(f"Error parsing {fname}: {e}")
    return emails

# 1. Parse Drafts and Sent
drafts = parse_maildir_folder(os.path.join(MAILDIR, ".Drafts"))
sent = parse_maildir_folder(os.path.join(MAILDIR, ".Sent"))
all_outgoing = drafts + sent

# 2. Check Briefing File
file_exists = False
file_content = ""
file_size = 0
file_created_during_task = False

if os.path.exists(BRIEFING_FILE):
    file_exists = True
    file_size = os.path.getsize(BRIEFING_FILE)
    file_mtime = os.path.getmtime(BRIEFING_FILE)
    file_created_during_task = file_mtime > TASK_START
    try:
        with open(BRIEFING_FILE, 'r', errors='replace') as f:
            file_content = f.read()
    except Exception as e:
        file_content = f"Error reading file: {e}"

# 3. Construct Result
result = {
    "drafts": drafts,
    "sent": sent,
    "all_outgoing": all_outgoing,
    "briefing_file": {
        "exists": file_exists,
        "content": file_content,
        "size": file_size,
        "created_during_task": file_created_during_task
    },
    "task_start": TASK_START,
    "timestamp": str(TASK_END)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(all_outgoing)} outgoing emails and briefing file status: {file_exists}")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="