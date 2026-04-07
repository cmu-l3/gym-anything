#!/bin/bash
echo "=== Exporting Support Ticket Acknowledgment Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Python Script to Parse Maildir
# ============================================================
# We need to analyze:
# 1. 'Tickets-Created' folder content (to verify moves)
# 2. 'Sent' folder content (to verify replies, templates, and IDs)

python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy
from datetime import datetime

MAILDIR = "/home/ga/Maildir"
TICKETS_DIR = os.path.join(MAILDIR, ".Tickets-Created")
SENT_DIR = os.path.join(MAILDIR, ".Sent")
TASK_START = int(open('/tmp/task_start_time.txt').read().strip())

def parse_maildir_folder(folder_path):
    emails = []
    if not os.path.exists(folder_path):
        return emails
    
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path):
            continue
            
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            try:
                # Get file stats
                stats = os.stat(fpath)
                created_time = stats.st_mtime
                
                with open(fpath, 'rb') as f:
                    msg = email.message_from_binary_file(f, policy=policy.default)
                    
                body = ""
                if msg.is_multipart():
                    for part in msg.walk():
                        if part.get_content_type() == "text/plain":
                            body = part.get_content()
                            break
                else:
                    body = msg.get_content()
                
                emails.append({
                    "subject": msg.get("subject", ""),
                    "from": msg.get("from", ""),
                    "to": msg.get("to", ""),
                    "date": msg.get("date", ""),
                    "body": body,
                    "filename": fname,
                    "mtime": created_time
                })
            except Exception as e:
                print(f"Error parsing {fname}: {e}")
                
    # Sort by time usually, but here just return list
    return emails

# 1. Analyze Tickets-Created
processed_emails = parse_maildir_folder(TICKETS_DIR)
tickets_folder_exists = os.path.isdir(TICKETS_DIR)

# 2. Analyze Sent Items (Created after task start)
all_sent = parse_maildir_folder(SENT_DIR)
new_sent_emails = [e for e in all_sent if e['mtime'] > TASK_START]

result = {
    "tickets_folder_exists": tickets_folder_exists,
    "processed_count": len(processed_emails),
    "processed_emails": processed_emails,
    "sent_count": len(new_sent_emails),
    "sent_emails": new_sent_emails,
    "task_start": TASK_START,
    "task_end": int(datetime.now().timestamp())
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(processed_emails)} processed emails and {len(new_sent_emails)} new sent emails.")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="