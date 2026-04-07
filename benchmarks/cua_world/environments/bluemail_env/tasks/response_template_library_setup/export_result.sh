#!/bin/bash
echo "=== Exporting response_template_library_setup results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# BlueMail running check
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# Run Python script to parse Maildir and generate JSON result
# We use Python because parsing emails in bash is fragile
python3 << 'PYEOF'
import os
import json
import email
from email import policy
import time

MAILDIR = "/home/ga/Maildir"
TEMPLATE_FOLDER_NAME = "Response-Templates" # Expected name (case insensitive check done below)
RESULTS = {
    "folder_created": False,
    "folder_name_found": None,
    "draft_count": 0,
    "templates_found": [],
    "reply_sent": False,
    "sent_reply_subject": None,
    "app_running": False
}

def parse_email_file(filepath):
    try:
        with open(filepath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        subject = msg.get("Subject", "")
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
        
        return {"subject": subject, "body": body}
    except Exception as e:
        return {"subject": "Error", "body": str(e)}

# 1. Check for Template Folder
found_folder = None
for entry in os.listdir(MAILDIR):
    if not entry.startswith('.'): continue
    
    # Maildir folders start with dot
    real_name = entry[1:] 
    if real_name.lower() == TEMPLATE_FOLDER_NAME.lower():
        found_folder = entry
        RESULTS["folder_created"] = True
        RESULTS["folder_name_found"] = real_name
        break

# 2. Analyze Templates if folder exists
if found_folder:
    folder_path = os.path.join(MAILDIR, found_folder)
    # Check both cur and new
    files = []
    for sub in ['cur', 'new']:
        p = os.path.join(folder_path, sub)
        if os.path.exists(p):
            files.extend([os.path.join(p, f) for f in os.listdir(p) if os.path.isfile(os.path.join(p, f))])
    
    RESULTS["draft_count"] = len(files)
    
    for fpath in files:
        parsed = parse_email_file(fpath)
        RESULTS["templates_found"].append(parsed)

# 3. Check Sent Folder for Reply
sent_path = os.path.join(MAILDIR, ".Sent")
sent_files = []
for sub in ['cur', 'new']:
    p = os.path.join(sent_path, sub)
    if os.path.exists(p):
        # Get files with full path
        sent_files.extend([(os.path.join(p, f), os.path.getmtime(os.path.join(p, f))) 
                          for f in os.listdir(p) if os.path.isfile(os.path.join(p, f))])

# Sort by time, newest first
sent_files.sort(key=lambda x: x[1], reverse=True)

# Look at the most recent few sent emails
for fpath, mtime in sent_files[:5]:
    parsed = parse_email_file(fpath)
    subj = parsed["subject"]
    body = parsed["body"]
    
    # Check if it looks like the acknowledgment reply
    # Must contain key phrase and look like a reply
    if "received it and are reviewing" in body and (subj.lower().startswith("re:") or "reply" in subj.lower()):
        RESULTS["reply_sent"] = True
        RESULTS["sent_reply_subject"] = subj
        break

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(RESULTS, f, indent=4)

PYEOF

# Add app running status to JSON using jq (safer than python append)
if command -v jq >/dev/null; then
    jq --arg app "$APP_RUNNING" '.app_running = ($app == "true")' /tmp/task_result.json > /tmp/task_result.tmp && mv /tmp/task_result.tmp /tmp/task_result.json
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="