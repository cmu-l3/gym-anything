#!/bin/bash
echo "=== Exporting executive_draft_rescue result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if BlueMail running
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# Parse Maildir state using Python
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
SENT_DIRS = [f"{MAILDIR}/.Sent/cur", f"{MAILDIR}/.Sent/new"]
DRAFTS_DIRS = [f"{MAILDIR}/.Drafts/cur", f"{MAILDIR}/.Drafts/new"]

def parse_emails(directories):
    results = []
    for d in directories:
        if not os.path.isdir(d):
            continue
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                try:
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
                        
                    results.append({
                        "to": msg.get("To", ""),
                        "subject": msg.get("Subject", ""),
                        "body": body,
                        "filename": fname
                    })
                except Exception as e:
                    print(f"Error parsing {fname}: {e}")
    return results

sent_emails = parse_emails(SENT_DIRS)
draft_emails = parse_emails(DRAFTS_DIRS)

result = {
    "sent_emails": sent_emails,
    "draft_emails": draft_emails,
    "bm_running": os.environ.get("BM_RUNNING") == "true",
    "timestamp": os.environ.get("TASK_END")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="