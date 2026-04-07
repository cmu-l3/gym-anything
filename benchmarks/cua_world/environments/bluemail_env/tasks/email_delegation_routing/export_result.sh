#!/bin/bash
echo "=== Exporting email_delegation_routing result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Capture task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_INBOX=$(cat /tmp/initial_inbox_count 2>/dev/null || echo "50")

# Run Python script to parse Sent and Drafts folders
# We parse content to verify routing accuracy
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
TASK_START = int(os.environ.get('TASK_START', 0))

def parse_maildir_folder(folder_path):
    """Parse all emails in a Maildir folder (cur and new)."""
    emails = []
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.isdir(path):
            continue
            
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if not os.path.isfile(fpath):
                continue
                
            # Check modification time to ensure it was created during task
            mtime = os.path.getmtime(fpath)
            if mtime < TASK_START:
                continue

            try:
                with open(fpath, 'rb') as f:
                    msg = email.message_from_binary_file(f, policy=policy.default)
                    
                # Extract simple body text
                body = ""
                if msg.is_multipart():
                    for part in msg.walk():
                        if part.get_content_type() == "text/plain":
                            try:
                                body += part.get_content()
                            except:
                                pass
                else:
                    try:
                        body = msg.get_content()
                    except:
                        pass
                
                # Normalize headers
                to_addr = str(msg['to']).lower() if msg['to'] else ""
                subject = str(msg['subject']) if msg['subject'] else ""
                
                emails.append({
                    'to': to_addr,
                    'subject': subject,
                    'body': body.lower(),  # Lowercase for easier keyword matching
                    'filename': fname
                })
            except Exception as e:
                print(f"Error parsing {fname}: {e}")
    return emails

# Parse Sent and Drafts
sent_emails = parse_maildir_folder(f"{MAILDIR}/.Sent")
draft_emails = parse_maildir_folder(f"{MAILDIR}/.Drafts")

# Count current inbox size (to verify agent didn't delete/move originals)
inbox_count = 0
for subdir in ['cur', 'new']:
    path = os.path.join(MAILDIR, subdir)
    if os.path.isdir(path):
        inbox_count += len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

result = {
    "sent_emails": sent_emails,
    "draft_emails": draft_emails,
    "final_inbox_count": inbox_count,
    "task_start_ts": TASK_START
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(sent_emails)} sent emails and {len(draft_emails)} drafts.")
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="