#!/bin/bash
echo "=== Exporting executive_impersonation_detection result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png ga
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
APP_RUNNING=$(pgrep -f "bluemail" > /dev/null && echo "true" || echo "false")

# 2. Analyze Maildir State
# We need to find where our tracked emails ended up.
# Using Python for robust Maildir parsing and JSON generation.

python3 << 'PYEOF'
import os
import json
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
TRACKING_IDS = {
    "bec_real_01": "real",
    "bec_real_02": "real",
    "bec_fake_01": "fake",
    "bec_fake_02": "fake",
    "bec_fake_03": "fake"
}

results = {
    "locations": {},
    "folders_created": [],
    "draft_report": None,
    "security_report_sent": None
}

def get_folder_name(path):
    # Convert filesystem path to logical folder name
    # e.g. /home/ga/Maildir/.BEC-Quarantine/cur -> BEC-Quarantine
    # e.g. /home/ga/Maildir/cur -> INBOX
    
    parts = path.split('/')
    if '.Drafts' in parts or '.Sent' in parts or '.Trash' in parts or '.Junk' in parts:
        # Standard folders
        for p in parts:
            if p.startswith('.'): return p[1:]
    
    if 'cur' in parts or 'new' in parts:
        # Check parent dir
        parent = os.path.dirname(path)
        if parent == MAILDIR:
            return "INBOX"
        basename = os.path.basename(parent)
        if basename.startswith('.'):
            return basename[1:] # Custom folder
            
    return "UNKNOWN"

def scan_maildir(root):
    # Recursive walk
    for dirpath, dirs, files in os.walk(root):
        # Identify logical folder
        folder = "UNKNOWN"
        if dirpath == f"{root}/cur" or dirpath == f"{root}/new":
            folder = "INBOX"
        elif dirpath.startswith(f"{root}/.") and ("/cur" in dirpath or "/new" in dirpath):
            # Extract folder name from path like /home/ga/Maildir/.FolderName/cur
            rel = os.path.relpath(dirpath, root)
            folder = rel.split('/')[0][1:] # strip dot
        
        # Record custom folders
        if folder not in ["INBOX", "UNKNOWN", "Drafts", "Sent", "Trash", "Junk"] and folder not in results["folders_created"]:
            results["folders_created"].append(folder)

        for f in files:
            path = os.path.join(dirpath, f)
            try:
                with open(path, 'rb') as fp:
                    msg = email.message_from_binary_file(fp, policy=policy.default)
                    
                    # check for tracking header
                    track_id = msg.get('X-BEC-Track')
                    if track_id and track_id in TRACKING_IDS:
                        results["locations"][track_id] = folder
                    
                    # check for draft/sent report
                    if folder in ["Drafts", "Sent"]:
                        to_addr = msg.get('To', '').lower()
                        subject = msg.get('Subject', '').lower()
                        if "security@company.com" in to_addr:
                            report_data = {
                                "subject": subject,
                                "body": msg.get_body(preferencelist=('plain')).get_content() if msg.get_body() else "",
                                "folder": folder
                            }
                            if folder == "Drafts":
                                results["draft_report"] = report_data
                            else:
                                results["security_report_sent"] = report_data
                                
            except Exception as e:
                continue

scan_maildir(MAILDIR)

# Output JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

PYEOF

# 3. Add Metadata
# (Using jq or simple cat appending would be messy, so relying on the python script above)

# Finalize permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="