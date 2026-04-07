#!/bin/bash
echo "=== Exporting release_feedback_synthesis result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if BlueMail is running
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# ============================================================
# PYTHON SCRIPT TO ANALYZE MAILDIR
# ============================================================
# We use Python to robustly parse Maildir files and extract subjects/bodies
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
TASK_START = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

def parse_eml(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        subject = msg.get('subject', '')
        to_addr = msg.get('to', '')
        
        # Simple body extraction (text/plain preference)
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
                
        return {
            'subject': subject,
            'to': to_addr,
            'body': body,
            'filename': os.path.basename(fpath)
        }
    except Exception as e:
        return {'subject': f"Error: {e}", 'to': '', 'body': '', 'filename': os.path.basename(fpath)}

# 1. FIND FLAGGED EMAILS
# Look for 'F' in the suffix of files in cur/ and new/
flagged_emails = []
for subdir in ['cur', 'new']:
    path = os.path.join(MAILDIR, subdir)
    if not os.path.exists(path): continue
    
    for fname in os.listdir(path):
        if 'F' in fname.split(':')[-1]: # Check flags section
            fpath = os.path.join(path, fname)
            data = parse_eml(fpath)
            # Only count if it seems to be in the Inbox (not Trash/Junk)
            # Since we look at ~/Maildir/cur directly, that is the Inbox.
            flagged_emails.append(data)

# 2. FIND DRAFTS
# Look in .Drafts folder
drafts = []
drafts_dir = os.path.join(MAILDIR, '.Drafts')
for subdir in ['cur', 'new']:
    path = os.path.join(drafts_dir, subdir)
    if not os.path.exists(path): continue
    
    for fname in os.listdir(path):
        fpath = os.path.join(path, fname)
        # Check modification time to ensure it was touched during task
        mtime = os.path.getmtime(fpath)
        if mtime > TASK_START:
            data = parse_eml(fpath)
            drafts.append(data)

result = {
    "flagged_emails": flagged_emails,
    "flagged_count": len(flagged_emails),
    "drafts": drafts,
    "draft_count": len(drafts),
    "app_running": True  # Passed in from bash via logic below, but we structure here
}

with open('/tmp/py_analysis.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Merge Python analysis with bash variables
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $(cat /tmp/py_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="