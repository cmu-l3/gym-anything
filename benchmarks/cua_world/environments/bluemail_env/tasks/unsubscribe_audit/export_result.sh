#!/bin/bash
echo "=== Exporting unsubscribe_audit result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python analysis script
# We do this in Python to handle parsing email headers robustly
python3 << 'PYEOF'
import os
import json
import re
import email
from email.policy import default

MAILDIR = "/home/ga/Maildir"
TASK_START_TIME = 0
try:
    with open('/tmp/task_start_time', 'r') as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

def parse_email_file(fpath):
    """Parse a single email file and return relevant metadata."""
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=default)
        
        # Extract body (simplistic text extraction)
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
            "subject": str(msg["subject"] or ""),
            "to": str(msg["to"] or ""),
            "from": str(msg["from"] or ""),
            "list_id": str(msg["List-Id"] or ""),
            "x_mailing_list": str(msg["X-Mailing-List"] or ""),
            "body": body.lower(),
            "path": fpath
        }
    except Exception as e:
        return {"error": str(e)}

def analyze_folder(folder_path):
    """Analyze all emails in a Maildir folder (cur/ and new/)."""
    emails = []
    if not os.path.exists(folder_path):
        return emails
        
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if os.path.isdir(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                if os.path.isfile(fpath):
                    data = parse_email_file(fpath)
                    emails.append(data)
    return emails

def find_unsubscribe_folder():
    """Find a folder named 'Unsubscribe' (case-insensitive)."""
    candidates = []
    for entry in os.listdir(MAILDIR):
        if not entry.startswith('.'): continue
        
        folder_name = entry[1:] # Strip leading dot
        if folder_name.lower() in ['unsubscribe', 'unsubscribe-audit', 'unsub']:
            full_path = os.path.join(MAILDIR, entry)
            candidates.append({
                "name": folder_name,
                "path": full_path,
                "emails": analyze_folder(full_path)
            })
    return candidates

# --- Main Analysis ---

result = {
    "task_start_time": TASK_START_TIME,
    "timestamp": os.popen("date -Iseconds").read().strip(),
    "bluemail_running": os.system("pgrep -f bluemail > /dev/null") == 0,
    "unsubscribe_folders": [],
    "drafts": [],
    "sent": [],
    "inbox_count": 0
}

# 1. Analyze Inbox (to check for reduction)
result["inbox_count"] = len(analyze_folder(os.path.join(MAILDIR))) # INBOX is root in Maildir layout often, or .INBOX
# Actually standard Dovecot with Layout=fs usually uses root for INBOX, but let's check standard layout
if os.path.exists(os.path.join(MAILDIR, "cur")):
    result["inbox_count"] = len(analyze_folder(MAILDIR))

# 2. Find and Analyze Unsubscribe Folder
found_folders = find_unsubscribe_folder()
result["unsubscribe_folders"] = found_folders

# 3. Analyze Drafts and Sent (for outgoing emails)
drafts_path = os.path.join(MAILDIR, ".Drafts")
sent_path = os.path.join(MAILDIR, ".Sent")
result["drafts"] = analyze_folder(drafts_path)
result["sent"] = analyze_folder(sent_path)

# 4. Extract mailing list identities from the moved emails
# We want to know if the agent moved emails from *different* lists
for folder in result["unsubscribe_folders"]:
    lists_found = set()
    for eml in folder["emails"]:
        # Try to identify list
        lid = eml.get("list_id", "")
        xml = eml.get("x_mailing_list", "")
        subj = eml.get("subject", "")
        
        # Heuristics
        if "spamassassin" in lid.lower() or "spamassassin" in xml.lower():
            lists_found.add("spamassassin")
        elif "ilug" in lid.lower() or "[ilug]" in subj.lower():
            lists_found.add("ilug")
        elif "zzzzteana" in lid.lower() or "zzzzteana" in xml.lower():
            lists_found.add("zzzzteana")
        elif "exmh" in lid.lower() or "exmh" in xml.lower():
            lists_found.add("exmh")
        elif "irr" in lid.lower():
            lists_found.add("irr")
        elif lid:
            lists_found.add(lid) # Fallback to raw ID
            
    folder["distinct_lists_detected"] = list(lists_found)
    folder["email_count"] = len(folder["emails"])

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="