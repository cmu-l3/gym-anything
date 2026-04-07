#!/bin/bash
echo "=== Exporting meeting_followup_drafts result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if BlueMail is running
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# Use Python to parse Maildir state and Draft content
# This is more reliable than bash for parsing headers and body text
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
TASK_START = int(open('/tmp/task_start_time').read().strip()) if os.path.exists('/tmp/task_start_time') else 0

def count_emails(path):
    if not os.path.exists(path): return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

def parse_eml(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
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
            "body": body,
            "mtime": os.path.getmtime(fpath)
        }
    except Exception as e:
        return {"error": str(e)}

# 1. Check Folder Existence and Population
meridian_folder_path = os.path.join(MAILDIR, ".Meridian-Q4")
folder_exists = os.path.isdir(meridian_folder_path)
folder_count = 0
if folder_exists:
    folder_count = count_emails(os.path.join(meridian_folder_path, "cur")) + \
                   count_emails(os.path.join(meridian_folder_path, "new"))

# 2. Check Inbox Reduction
inbox_count = count_emails(os.path.join(MAILDIR, "cur")) + \
              count_emails(os.path.join(MAILDIR, "new"))

# 3. Parse Drafts
drafts = []
draft_dirs = [os.path.join(MAILDIR, ".Drafts", "cur"), os.path.join(MAILDIR, ".Drafts", "new")]
for d in draft_dirs:
    if os.path.exists(d):
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                # Only consider drafts created/modified after task start
                if os.path.getmtime(fpath) > TASK_START:
                    drafts.append(parse_eml(fpath))

# 4. Check Sent items (in case user accidentally sent them)
sent_emails = []
sent_dirs = [os.path.join(MAILDIR, ".Sent", "cur"), os.path.join(MAILDIR, ".Sent", "new")]
for d in sent_dirs:
    if os.path.exists(d):
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                if os.path.getmtime(fpath) > TASK_START:
                    sent_emails.append(parse_eml(fpath))

result = {
    "folder_exists": folder_exists,
    "folder_email_count": folder_count,
    "current_inbox_count": inbox_count,
    "drafts": drafts,
    "sent_emails": sent_emails,
    "app_running": True  # Passed in via shell var if needed, but handled by wrapper usually
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Add App Running status to JSON
if [ -f /tmp/task_result.json ]; then
    # Use jq to update if available, or simple text append if necessary. 
    # Python script above handles the main logic, but let's inject APP_RUNNING just in case
    # The python script above hardcoded it to True, let's fix it based on bash variable
    if [ "$APP_RUNNING" = "false" ]; then
        sed -i 's/"app_running": true/"app_running": false/' /tmp/task_result.json
    fi
    
    # Add screenshot path
    sed -i 's/}$/,\n  "screenshot_path": "\/tmp\/task_final.png"\n}/' /tmp/task_result.json
fi

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="