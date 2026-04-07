#!/bin/bash
# Export script for incident_triage_and_summary
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check App State
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# 3. Analyze Maildir using Python
#    We need to:
#    - Find created folders (Triage/Critical, etc.)
#    - Count emails in them
#    - Check subjects for keywords
#    - Find the Sent reply
#    - Find the Draft/Sent summary report
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
CRITICAL_KEYWORDS = ["error", "fail", "failure", "fatal"]
WARNING_KEYWORDS = ["check", "review", "warning"]

def parse_email_file(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        subject = msg.get("Subject", "")
        to_addr = msg.get("To", "")
        body = ""
        
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    try:
                        body = part.get_content()
                        break
                    except: pass
        else:
            try:
                body = msg.get_content()
            except: pass
            
        return {
            "subject": subject,
            "to": to_addr,
            "body": body,
            "in_reply_to": msg.get("In-Reply-To", "")
        }
    except Exception as e:
        return {"subject": "", "error": str(e)}

def scan_folder(folder_path):
    emails = []
    if not os.path.exists(folder_path):
        return emails
    
    for subdir in ["cur", "new"]:
        path = os.path.join(folder_path, subdir)
        if os.path.isdir(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                if os.path.isfile(fpath):
                    data = parse_email_file(fpath)
                    emails.append(data)
    return emails

# Find Triage folders (BlueMail might name them .Triage.Critical or just .Critical depending on creation)
# We will look for folders containing "Critical" or "Warning" in their name
critical_emails = []
warning_emails = []
folders_found = []

for entry in os.listdir(MAILDIR):
    if not entry.startswith("."): continue
    
    clean_name = entry.lstrip(".")
    full_path = os.path.join(MAILDIR, entry)
    
    if "critical" in clean_name.lower():
        folders_found.append("Critical")
        critical_emails.extend(scan_folder(full_path))
    elif "warning" in clean_name.lower():
        folders_found.append("Warning")
        warning_emails.extend(scan_folder(full_path))

# Check categorization accuracy
critical_correct_count = 0
for em in critical_emails:
    subj = em.get("subject", "").lower()
    if any(k in subj for k in CRITICAL_KEYWORDS):
        critical_correct_count += 1

warning_correct_count = 0
for em in warning_emails:
    subj = em.get("subject", "").lower()
    if any(k in subj for k in WARNING_KEYWORDS):
        warning_correct_count += 1

# Check Drafts/Sent for Summary and Reply
outgoing_emails = []
for folder in [".Drafts", ".Sent"]:
    outgoing_emails.extend(scan_folder(os.path.join(MAILDIR, folder)))

reply_found = False
summary_found = False
summary_body = ""
summary_subject = ""

for em in outgoing_emails:
    subj = em.get("subject", "").lower()
    body = em.get("body", "").lower()
    to_addr = em.get("to", "").lower()
    
    # Check for Reply
    if "investigating" in body and "acknowledged" in body:
        reply_found = True
        
    # Check for Summary
    if "sre-leads@company.com" in to_addr:
        summary_found = True
        summary_body = em.get("body", "")
        summary_subject = em.get("subject", "")

result = {
    "folders_found": folders_found,
    "critical_count": len(critical_emails),
    "warning_count": len(warning_emails),
    "critical_correct_keyword_count": critical_correct_count,
    "warning_correct_keyword_count": warning_correct_count,
    "reply_found": reply_found,
    "summary_found": summary_found,
    "summary_body": summary_body,
    "summary_subject": summary_subject,
    "app_running": os.environ.get("APP_RUNNING") == "true"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to final location with permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json