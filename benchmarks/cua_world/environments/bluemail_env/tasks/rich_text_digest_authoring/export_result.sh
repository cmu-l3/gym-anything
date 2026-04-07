#!/bin/bash
echo "=== Exporting rich_text_digest_authoring result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if BlueMail is running
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# Use Python to parse the draft and the inbox (for verification data)
python3 << 'PYEOF'
import os
import json
import email
from email import policy
from email.parser import BytesParser

MAILDIR = "/home/ga/Maildir"
DRAFTS_DIRS = [os.path.join(MAILDIR, ".Drafts", "cur"), os.path.join(MAILDIR, ".Drafts", "new")]
INBOX_DIRS = [os.path.join(MAILDIR, "cur"), os.path.join(MAILDIR, "new")]

result = {
    "draft_found": False,
    "recipient": "",
    "subject": "",
    "html_body": "",
    "text_body": "",
    "inbox_subjects": []
}

# 1. Parse the most recent Draft
try:
    draft_files = []
    for d in DRAFTS_DIRS:
        if os.path.exists(d):
            for f in os.listdir(d):
                full_path = os.path.join(d, f)
                if os.path.isfile(full_path):
                    draft_files.append(full_path)
    
    # Sort by mtime to get the latest
    draft_files.sort(key=os.path.getmtime, reverse=True)

    if draft_files:
        latest_draft = draft_files[0]
        with open(latest_draft, 'rb') as fp:
            msg = BytesParser(policy=policy.default).parse(fp)
        
        result["draft_found"] = True
        result["recipient"] = str(msg['to']).strip()
        result["subject"] = str(msg['subject']).strip()
        
        # Extract body
        if msg.is_multipart():
            for part in msg.walk():
                ctype = part.get_content_type()
                cdispo = str(part.get('Content-Disposition'))
                
                if ctype == 'text/html' and 'attachment' not in cdispo:
                    try:
                        result["html_body"] = part.get_content()
                    except:
                        result["html_body"] = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                elif ctype == 'text/plain' and 'attachment' not in cdispo:
                    try:
                        result["text_body"] = part.get_content()
                    except:
                        result["text_body"] = part.get_payload(decode=True).decode('utf-8', errors='ignore')
        else:
            try:
                content = msg.get_content()
            except:
                content = msg.get_payload(decode=True).decode('utf-8', errors='ignore')
                
            if msg.get_content_type() == 'text/html':
                result["html_body"] = content
            else:
                result["text_body"] = content
except Exception as e:
    result["error_draft"] = str(e)

# 2. Collect all Inbox Subjects (Ground Truth)
try:
    subjects = []
    for d in INBOX_DIRS:
        if os.path.exists(d):
            for f in os.listdir(d):
                if not f.startswith('.'):
                    full_path = os.path.join(d, f)
                    try:
                        with open(full_path, 'rb') as fp:
                            # Just read headers to be fast
                            m = BytesParser(policy=policy.default).parse(fp, headersonly=True)
                            subj = str(m['subject']).strip()
                            if subj:
                                subjects.append(subj)
                    except:
                        pass
    result["inbox_subjects"] = subjects
except Exception as e:
    result["error_inbox"] = str(e)

# Add app running state passed from bash
result["bluemail_running"] = os.environ.get("BM_RUNNING") == "true"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export complete ==="