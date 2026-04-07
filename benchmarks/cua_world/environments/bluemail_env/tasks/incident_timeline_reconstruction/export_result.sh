#!/bin/bash
echo "=== Exporting Incident Timeline Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Run Python Analysis Script
# We use Python to parse Maildir structures and email content reliably
python3 << 'PYEOF'
import os
import json
import re
import time
import email
from email import policy
from email.parser import BytesParser

MAILDIR = "/home/ga/Maildir"
TASK_START_FILE = "/tmp/task_start_time"
INITIAL_COUNT_FILE = "/tmp/initial_inbox_count"

def get_task_start_time():
    try:
        with open(TASK_START_FILE, 'r') as f:
            return int(f.read().strip())
    except:
        return 0

def parse_email_file(fpath):
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
            "to": str(msg['to']),
            "subject": str(msg['subject']),
            "body": body[:5000]  # Limit body size
        }
    except Exception as e:
        return {"error": str(e)}

def count_emails(path):
    if not os.path.exists(path): return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

# --- Main Analysis ---

result = {
    "timestamp": time.time(),
    "bluemail_running": False
}

# Check process
if os.system("pgrep -f bluemail > /dev/null") == 0:
    result["bluemail_running"] = True

# Inbox Count
inbox_path = os.path.join(MAILDIR, "cur")
result["current_inbox_count"] = count_emails(inbox_path) + count_emails(os.path.join(MAILDIR, "new"))

# Custom Folders Check
result["custom_folders"] = {}
result["evidence_folder_found"] = False
result["evidence_folder_count"] = 0

for item in os.listdir(MAILDIR):
    if item.startswith(".") and item not in ['.Drafts', '.Sent', '.Trash', '.Junk', '.Archive']:
        folder_name = item[1:] # Remove leading dot
        folder_path = os.path.join(MAILDIR, item)
        if os.path.isdir(folder_path):
            count = count_emails(os.path.join(folder_path, "cur")) + count_emails(os.path.join(folder_path, "new"))
            result["custom_folders"][folder_name] = count
            
            # Check if this is the target folder (fuzzy match)
            if "postmortem" in folder_name.lower() or "evidence" in folder_name.lower():
                result["evidence_folder_found"] = True
                result["evidence_folder_count"] = count

# Drafts & Sent Analysis
result["drafts_and_sent"] = []

for folder in ['.Drafts', '.Sent']:
    for sub in ['cur', 'new']:
        path = os.path.join(MAILDIR, folder, sub)
        if os.path.exists(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                if os.path.isfile(fpath):
                    # Check modification time to ensure it was created during task
                    mtime = os.path.getmtime(fpath)
                    if mtime > get_task_start_time():
                        parsed = parse_email_file(fpath)
                        parsed['folder'] = folder
                        result["drafts_and_sent"].append(parsed)

# Save Result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Python analysis complete.")
PYEOF

# 3. Secure output file
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="