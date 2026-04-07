#!/bin/bash
echo "=== Exporting multi_client_inbox_partitioning result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze Maildir using Python to verify:
# 1. Folder structure (.Clients.Apache, .Clients.ILUG)
# 2. Content of emails in folders (keyword matching)
# 3. Flags of emails in folders (F for flagged, absence of S for unread)
# 4. Draft email existence

python3 << 'PYEOF'
import os
import json
import re

MAILDIR = "/home/ga/Maildir"
RESULT_FILE = "/tmp/task_result.json"

def get_emails_in_folder(folder_path):
    """Returns list of dicts {filename, content, flags}"""
    emails = []
    if not os.path.exists(folder_path):
        return emails
        
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.isdir(path):
            continue
            
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if not os.path.isfile(fpath):
                continue
                
            # Parse flags from filename (e.g., ...:2,FS)
            flags = ""
            if ":2," in fname:
                flags = fname.split(":2,")[1]
            
            # Read content (header + start of body)
            try:
                with open(fpath, 'r', errors='ignore') as f:
                    content = f.read(5000).lower()
            except:
                content = ""
                
            emails.append({
                'filename': fname,
                'flags': flags,
                'content': content,
                'subdir': subdir
            })
    return emails

def check_content_match(emails, keywords):
    count = 0
    for e in emails:
        if any(k in e['content'] for k in keywords):
            count += 1
    return count

# check folders
# Maildir folders usually use dot separator for hierarchy: .Clients.Apache
clients_apache_path = os.path.join(MAILDIR, ".Clients.Apache")
clients_ilug_path = os.path.join(MAILDIR, ".Clients.ILUG")

apache_exists = os.path.isdir(clients_apache_path)
ilug_exists = os.path.isdir(clients_ilug_path)

apache_emails = get_emails_in_folder(clients_apache_path)
ilug_emails = get_emails_in_folder(clients_ilug_path)

# Verify Sorting Content
# Apache keywords: spamassassin, spam, apache, sa-talk, sadev
# ILUG keywords: ilug, irish, linux, dublin
apache_content_match_count = check_content_match(apache_emails, ["spamassassin", "apache", "sa-talk", "sadev", "sourceforge"])
ilug_content_match_count = check_content_match(ilug_emails, ["ilug", "irish", "linux", "dublin"])

# Verify States
# Apache should be Flagged (look for 'F' in flags)
apache_flagged_count = sum(1 for e in apache_emails if 'F' in e['flags'])

# ILUG should be Unread (no 'S' in flags OR in 'new' subdir)
# Note: 'new' subdir implies unread in Maildir standard. 'cur' without 'S' also means unread.
ilug_unread_count = sum(1 for e in ilug_emails if 'S' not in e['flags'] or e['subdir'] == 'new')

# Check Drafts
drafts_path = os.path.join(MAILDIR, ".Drafts")
drafts = get_emails_in_folder(drafts_path)
report_draft_found = False
for d in drafts:
    # Check subject/body for keywords
    if "billing@consultancy.firm" in d['content'] and "weekly triage report" in d['content']:
        report_draft_found = True
        break

result = {
    "apache_folder_exists": apache_exists,
    "ilug_folder_exists": ilug_exists,
    "apache_email_count": len(apache_emails),
    "ilug_email_count": len(ilug_emails),
    "apache_content_correct_count": apache_content_match_count,
    "ilug_content_correct_count": ilug_content_match_count,
    "apache_flagged_count": apache_flagged_count,
    "ilug_unread_count": ilug_unread_count,
    "report_draft_found": report_draft_found
}

with open(RESULT_FILE, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="