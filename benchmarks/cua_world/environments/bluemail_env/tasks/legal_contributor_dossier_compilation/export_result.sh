#!/bin/bash
# Export script for legal_contributor_dossier_compilation
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Python Script to Analyze Maildir Content
# This script will:
# - Locate the created folders (handling fuzzy naming like Dossier-Mason/Direct or Dossier-Mason.Direct)
# - Analyze contents of Direct folder (check From headers)
# - Analyze contents of Mentions folder (check From headers AND Body content)
# - Check Drafts/Sent for the report

python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
TARGET_EMAIL = "jm@jmason.org"
KEYWORDS = ["justin mason", "jmason"]

def parse_email_file(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        body = ""
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    try:
                        body += part.get_content()
                    except: pass
        else:
            try:
                body = msg.get_content()
            except: pass
            
        return {
            "from": str(msg.get("from", "")).lower(),
            "to": str(msg.get("to", "")).lower(),
            "subject": str(msg.get("subject", "")).lower(),
            "body": body.lower()
        }
    except Exception as e:
        return {"error": str(e), "from": "", "body": ""}

def scan_folder(folder_path):
    emails = []
    if not os.path.exists(folder_path):
        return emails
        
    for subdir in ["cur", "new"]:
        path = os.path.join(folder_path, subdir)
        if os.path.isdir(path):
            for fname in os.listdir(path):
                if not fname.startswith("."):
                    data = parse_email_file(os.path.join(path, fname))
                    emails.append(data)
    return emails

result = {
    "direct_folder_found": False,
    "mentions_folder_found": False,
    "direct_emails": [],
    "mentions_emails": [],
    "report_emails": [],
    "folder_structure": []
}

# Scan all folders to find the relevant ones
# Expected: .Dossier-Mason.Direct or .Dossier-Mason.Mentions or similar
for entry in os.listdir(MAILDIR):
    if not entry.startswith("."): continue
    
    clean_name = entry[1:] # Remove leading dot
    result["folder_structure"].append(clean_name)
    
    # Identify Direct Folder
    if "dossier" in clean_name.lower() and "direct" in clean_name.lower():
        result["direct_folder_found"] = True
        result["direct_emails"] = scan_folder(os.path.join(MAILDIR, entry))
        
    # Identify Mentions Folder
    if "dossier" in clean_name.lower() and "mention" in clean_name.lower():
        result["mentions_folder_found"] = True
        result["mentions_emails"] = scan_folder(os.path.join(MAILDIR, entry))

# Scan Drafts and Sent for the report
report_candidates = []
for folder in [".Drafts", ".Sent"]:
    f_emails = scan_folder(os.path.join(MAILDIR, folder))
    for em in f_emails:
        if "legal-audit" in em["to"] or "discovery" in em["subject"]:
            result["report_emails"].append(em)

# Analyze stats for verification
result["stats"] = {
    "direct_count": len(result["direct_emails"]),
    "mentions_count": len(result["mentions_emails"]),
    # Check correctness of Direct folder
    "direct_correct_sender": sum(1 for e in result["direct_emails"] if TARGET_EMAIL in e["from"]),
    # Check correctness of Mentions folder
    "mentions_contain_keyword": sum(1 for e in result["mentions_emails"] if any(k in e["body"] or k in e["subject"] for k in KEYWORDS)),
    "mentions_from_target": sum(1 for e in result["mentions_emails"] if TARGET_EMAIL in e["from"]),
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="