#!/bin/bash
echo "=== Exporting reply_and_forward result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if BlueMail is running
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script to parse Sent and Drafts folders
# We extract headers and body content to verify against task requirements
python3 << 'PYEOF'
import os
import json
import email
from email import policy
import time
import re

MAILDIR = "/home/ga/Maildir"
TASK_START = int(os.environ.get('TASK_START', 0))

def parse_maildir_folder(folder_path):
    """Parse all emails in a Maildir folder (cur and new)."""
    emails = []
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path):
            continue
            
        for filename in os.listdir(path):
            filepath = os.path.join(path, filename)
            if not os.path.isfile(filepath):
                continue
                
            # Check file modification time (anti-gaming)
            mtime = os.path.getmtime(filepath)
            if mtime < TASK_START:
                continue

            try:
                with open(filepath, 'rb') as f:
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
                        # Fallback for some encodings
                        try:
                            with open(filepath, 'r', errors='ignore') as f2:
                                body = f2.read()
                        except:
                            pass
                            
                emails.append({
                    'to': str(msg['to']),
                    'from': str(msg['from']),
                    'subject': str(msg['subject']),
                    'in_reply_to': str(msg['in-reply-to']),
                    'references': str(msg['references']),
                    'body': body.lower(),  # Normalized for easier searching
                    'filename': filename,
                    'timestamp': mtime
                })
            except Exception as e:
                print(f"Error parsing {filename}: {e}")
                
    return emails

# Parse Sent and Drafts
sent_emails = parse_maildir_folder(os.path.join(MAILDIR, '.Sent'))
draft_emails = parse_maildir_folder(os.path.join(MAILDIR, '.Drafts'))

# Combine for verification (agent can send OR save as draft)
all_actions = sent_emails + draft_emails

result = {
    'bluemail_running': os.environ.get('BM_RUNNING') == 'true',
    'actions': all_actions,
    'action_count': len(all_actions),
    'timestamp': time.time()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(all_actions)} new email actions (Sent+Drafts)")
PYEOF

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="