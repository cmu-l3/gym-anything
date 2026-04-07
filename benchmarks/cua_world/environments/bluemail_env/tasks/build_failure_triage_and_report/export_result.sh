#!/bin/bash
echo "=== Exporting Build Failure Triage Result ==="

source /workspace/scripts/task_utils.sh

# Directories
MAILDIR="/home/ga/Maildir"
LOG_FILE="/home/ga/Documents/triage_log.txt"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Python script to analyze Maildir state and export details
python3 << 'EOF'
import os
import json
import re

maildir = "/home/ga/Maildir"
target_folders = [".Build-Alerts", ".BuildAlerts", ".build-alerts", ".buildalerts"]
found_folder_path = None
folder_name_used = None

# Find if the folder exists (handle case variations)
for item in os.listdir(maildir):
    if f".{item}" in target_folders or item in target_folders or f".{item}".lower() in target_folders:
        found_folder_path = os.path.join(maildir, item)
        folder_name_used = item
        break

emails_in_target = []
unread_count = 0

if found_folder_path:
    for subdir in ["cur", "new"]:
        path = os.path.join(found_folder_path, subdir)
        if os.path.exists(path):
            for filename in os.listdir(path):
                filepath = os.path.join(path, filename)
                if os.path.isfile(filepath):
                    # Check flags in filename (Maildir spec)
                    # "S" in flags means Seen (Read). Absence means Unread.
                    flags = filename.split(":")[-1] if ":" in filename else ""
                    is_unread = "S" not in flags
                    
                    if is_unread:
                        unread_count += 1
                    
                    # Extract subject
                    subject = "(No Subject)"
                    try:
                        with open(filepath, 'r', errors='ignore') as f:
                            for line in f:
                                if line.lower().startswith("subject:"):
                                    subject = line[8:].strip()
                                    break
                    except:
                        pass
                    
                    emails_in_target.append({
                        "subject": subject,
                        "is_unread": is_unread,
                        "filename": filename
                    })

# Analyze Sent folder for escalation
escalation_email = None
sent_dir = os.path.join(maildir, ".Sent", "cur")
if os.path.exists(sent_dir):
    # Sort by time, newest first
    files = sorted([os.path.join(sent_dir, f) for f in os.listdir(sent_dir)], key=os.path.getmtime, reverse=True)
    for filepath in files[:5]: # Check last 5 sent emails
        try:
            with open(filepath, 'r', errors='ignore') as f:
                content = f.read()
                
            # Simple parsing
            headers = {}
            body = ""
            in_body = False
            for line in content.split('\n'):
                if not in_body:
                    if line.strip() == "":
                        in_body = True
                        continue
                    if ":" in line:
                        k, v = line.split(":", 1)
                        headers[k.lower()] = v.strip()
                else:
                    body += line + "\n"
            
            if "build-master@company.com" in headers.get("to", ""):
                escalation_email = {
                    "to": headers.get("to", ""),
                    "subject": headers.get("subject", ""),
                    "body_snippet": body[:500]
                }
                break
        except:
            continue

# Read Log File
log_content = []
log_file_path = "/home/ga/Documents/triage_log.txt"
if os.path.exists(log_file_path):
    with open(log_file_path, 'r', errors='ignore') as f:
        log_content = [line.strip() for line in f.readlines() if line.strip()]

# Prepare Result JSON
result = {
    "folder_created": found_folder_path is not None,
    "folder_name": folder_name_used,
    "email_count": len(emails_in_target),
    "unread_count": unread_count,
    "emails": emails_in_target,
    "escalation_sent": escalation_email is not None,
    "escalation_details": escalation_email,
    "log_file_exists": os.path.exists(log_file_path),
    "log_entries": log_content
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json