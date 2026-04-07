#!/bin/bash
echo "=== Exporting Conference Itinerary Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final.png ga

# Task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper python script to analyze Maildir content
# We need to check:
# 1. Does .Dublin-Events folder exist?
# 2. What emails are in it? (Subject/Body keywords)
# 3. What is in .Sent? (Recipient, Subject, Body)

cat > /tmp/analyze_maildir.py << 'PYEOF'
import os
import email
from email import policy
import json
import sys

maildir_root = "/home/ga/Maildir"
target_folder_name = "Dublin-Events" # The task asks for this specific name
sent_folder_path = os.path.join(maildir_root, ".Sent", "cur")
target_folder_path = os.path.join(maildir_root, f".{target_folder_name}", "cur")

# Keywords to check for relevance in moved emails
keywords = ["pub", "beer", "social", "dinner", "meetup", "gathering", "drink"]

def parse_email_file(filepath):
    try:
        with open(filepath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        subject = msg.get('subject', '').strip()
        to = msg.get('to', '').strip()
        
        body = ""
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    body += part.get_content()
        else:
            body = msg.get_content()
            
        return {
            "subject": subject,
            "to": to,
            "body": body,
            "filepath": filepath
        }
    except Exception as e:
        return {"error": str(e)}

result = {
    "folder_created": False,
    "emails_in_folder": [],
    "sent_emails": [],
    "folder_path": target_folder_path
}

# Check target folder
# Note: Maildir folders often start with '.' in the filesystem
# We check case-insensitive match if exact missing
found_path = None
if os.path.exists(target_folder_path):
    found_path = target_folder_path
else:
    # Try case insensitive search
    for d in os.listdir(maildir_root):
        if d.lower() == f".{target_folder_name.lower()}":
            found_path = os.path.join(maildir_root, d, "cur")
            break

if found_path and os.path.isdir(found_path):
    result["folder_created"] = True
    # Parse emails in this folder
    if os.path.exists(found_path):
        for f in os.listdir(found_path):
            if os.path.isfile(os.path.join(found_path, f)):
                data = parse_email_file(os.path.join(found_path, f))
                # Check keywords
                content = (data.get("subject", "") + " " + data.get("body", "")).lower()
                data["has_keyword"] = any(k in content for k in keywords)
                result["emails_in_folder"].append(data)

# Check sent emails
if os.path.exists(sent_folder_path):
    for f in os.listdir(sent_folder_path):
        if os.path.isfile(os.path.join(sent_folder_path, f)):
            # Only check files modified/created after task start ideally, 
            # but folder was cleared at start so all are new
            result["sent_emails"].append(parse_email_file(os.path.join(sent_folder_path, f)))

print(json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_JSON=$(python3 /tmp/analyze_maildir.py)

# Check if BlueMail is running
APP_RUNNING=$(pgrep -f "bluemail" > /dev/null && echo "true" || echo "false")

# Assemble final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "maildir_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="