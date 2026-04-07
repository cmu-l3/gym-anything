#!/bin/bash
# Export script for project_timeline_archival
echo "=== Exporting project_timeline_archival result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State Visuals
take_screenshot /tmp/task_final.png

# 2. Check App State
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# 3. Analyze Maildir using Python
# We need to export:
# - Contents of 'Project-Exmh' folder (headers, dates) to determine ground truth
# - Contents of 'Sent' folder to verify actions
# - Folder existence check

python3 << 'PYEOF'
import os
import json
import email
from email.utils import parsedate_to_datetime
import datetime

MAILDIR = "/home/ga/Maildir"
PROJECT_FOLDER_NAME = "Project-Exmh"
RESULT_FILE = "/tmp/task_result.json"

def get_folder_path(folder_name):
    # Maildir folders start with dot
    return os.path.join(MAILDIR, f".{folder_name}")

def parse_eml_files(folder_path):
    emails = []
    if not os.path.exists(folder_path):
        return emails
        
    for subdir in ["cur", "new"]:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path):
            continue
            
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if not os.path.isfile(fpath):
                continue
                
            try:
                with open(fpath, "rb") as f:
                    msg = email.message_from_binary_file(f)
                    
                # Extract key fields
                subject = msg.get("Subject", "")
                date_str = msg.get("Date", "")
                msg_id = msg.get("Message-ID", "").strip()
                in_reply_to = msg.get("In-Reply-To", "").strip()
                to_addr = msg.get("To", "")
                
                # Parse date for sorting
                try:
                    dt = parsedate_to_datetime(date_str)
                    timestamp = dt.timestamp()
                except:
                    timestamp = 0
                    
                emails.append({
                    "file": fname,
                    "subject": subject,
                    "date": date_str,
                    "timestamp": timestamp,
                    "message_id": msg_id,
                    "in_reply_to": in_reply_to,
                    "to": to_addr,
                    "body_snippet": str(msg.get_payload())[:100] if not msg.is_multipart() else "multipart"
                })
            except Exception as e:
                print(f"Error parsing {fname}: {e}")
                continue
    return emails

# 1. Inspect Project Folder
project_folder_path = get_folder_path(PROJECT_FOLDER_NAME)
project_emails = parse_eml_files(project_folder_path)
folder_exists = os.path.exists(project_folder_path)

# 2. Inspect Sent Folder
sent_folder_path = get_folder_path("Sent")
sent_emails = parse_eml_files(sent_folder_path)

# 3. Inspect Inbox (for cleanup check)
inbox_emails = []
for subdir in ["cur", "new"]:
    path = os.path.join(MAILDIR, subdir)
    if os.path.exists(path):
        inbox_emails.extend(os.listdir(path))

result = {
    "folder_exists": folder_exists,
    "project_emails": project_emails,
    "sent_emails": sent_emails,
    "inbox_count": len(inbox_emails),
    "app_running": os.environ.get("APP_RUNNING") == "true",
    "timestamp": datetime.datetime.now().isoformat()
}

with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(project_emails)} project emails and {len(sent_emails)} sent emails.")
PYEOF

# 4. Final Cleanup
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="