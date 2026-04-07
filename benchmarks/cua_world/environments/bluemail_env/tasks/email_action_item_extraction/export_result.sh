#!/bin/bash
# Export script for email_action_item_extraction task
echo "=== Exporting email_action_item_extraction result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to analyze Maildir structure and content
python3 << 'PYEOF'
import os
import json
import re

MAILDIR = "/home/ga/Maildir"
TARGET_FOLDER = "Action-Required"

def get_email_content(filepath):
    """Simple parser to get subject and body start."""
    try:
        with open(filepath, 'r', errors='ignore') as f:
            content = f.read(10000) # Read first 10KB
            
        headers = {}
        body_lines = []
        in_body = False
        
        lines = content.splitlines()
        for line in lines:
            if not in_body:
                if line.strip() == "":
                    in_body = True
                    continue
                # Simple header parsing
                if ":" in line:
                    parts = line.split(":", 1)
                    key = parts[0].lower().strip()
                    val = parts[1].strip()
                    if key not in headers:
                        headers[key] = val
            else:
                body_lines.append(line)
                if len(body_lines) > 50: # Limit body capture
                    break
                    
        return {
            "to": headers.get("to", ""),
            "subject": headers.get("subject", ""),
            "cc": headers.get("cc", ""),
            "body": "\n".join(body_lines).lower()
        }
    except Exception as e:
        return {"error": str(e)}

def count_emails(folder_path):
    count = 0
    files = []
    for subdir in ["cur", "new"]:
        path = os.path.join(folder_path, subdir)
        if os.path.exists(path):
            for f in os.listdir(path):
                fpath = os.path.join(path, f)
                if os.path.isfile(fpath):
                    count += 1
                    files.append(fpath)
    return count, files

# 1. Analyze Action-Required folder
target_folder_path = os.path.join(MAILDIR, "." + TARGET_FOLDER)
folder_exists = os.path.isdir(target_folder_path)
folder_email_count = 0
folder_emails_content = []

if folder_exists:
    folder_email_count, file_paths = count_emails(target_folder_path)
    for fp in file_paths:
        folder_emails_content.append(get_email_content(fp))

# 2. Analyze Inbox (for reduction check)
inbox_count, _ = count_emails(MAILDIR)

# 3. Analyze Drafts and Sent (for summary email)
drafts = []
sent = []

drafts_path = os.path.join(MAILDIR, ".Drafts")
if os.path.isdir(drafts_path):
    _, d_files = count_emails(drafts_path)
    for fp in d_files:
        drafts.append(get_email_content(fp))

sent_path = os.path.join(MAILDIR, ".Sent")
if os.path.isdir(sent_path):
    _, s_files = count_emails(sent_path)
    for fp in s_files:
        sent.append(get_email_content(fp))

# 4. Construct Result
result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "folder_exists": folder_exists,
    "folder_name": TARGET_FOLDER,
    "folder_email_count": folder_email_count,
    "folder_emails_content": folder_emails_content,
    "final_inbox_count": inbox_count,
    "drafts": drafts,
    "sent": sent
}

# Write to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="