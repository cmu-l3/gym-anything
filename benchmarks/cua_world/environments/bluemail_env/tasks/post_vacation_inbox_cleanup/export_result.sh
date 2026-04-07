#!/bin/bash
echo "=== Exporting post_vacation_inbox_cleanup results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final_state.png

# Record task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper python script to analyze Maildir without relying on complex bash
python3 << 'PYEOF'
import os
import json
import re
import glob

MAILDIR = "/home/ga/Maildir"
TASK_START = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

def get_emails_in_folder(folder_path):
    """Return list of email files in cur/ and new/ subdirs."""
    emails = []
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if os.path.isdir(path):
            emails.extend([os.path.join(path, f) for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])
    return emails

def parse_email_content(filepath):
    """Extract simple headers and body snippet."""
    try:
        with open(filepath, 'r', errors='ignore') as f:
            content = f.read(4096) # Read first 4KB
        
        headers = {}
        body = ""
        in_body = False
        
        lines = content.split('\n')
        for line in lines:
            if in_body:
                body += line + " "
                if len(body) > 500: break
                continue
            
            if line.strip() == "":
                in_body = True
                continue
                
            match = re.match(r'^([\w-]+):\s*(.*)', line)
            if match:
                key = match.group(1).lower()
                headers[key] = match.group(2).strip()
                
        return {
            'to': headers.get('to', ''),
            'subject': headers.get('subject', ''),
            'body': body.strip()
        }
    except Exception:
        return {'to': '', 'subject': '', 'body': ''}

# 1. Analyze Flags (Across ALL folders)
# Dovecot stores flags in filename suffix. 'F' = Flagged/Starred.
flagged_count = 0
flagged_files = glob.glob(f"{MAILDIR}/**/cur/*:2,*F*", recursive=True) + \
                glob.glob(f"{MAILDIR}/**/new/*:2,*F*", recursive=True)
flagged_count = len(flagged_files)

# 2. Analyze Trash
trash_path = os.path.join(MAILDIR, ".Trash")
trash_emails = get_emails_in_folder(trash_path)
trash_count = len(trash_emails)
# Check modification times for anti-gaming (must be modified after task start)
trash_new_count = sum(1 for f in trash_emails if os.path.getmtime(f) > TASK_START)

# 3. Analyze Archive Folder
# Look for any folder matching 'Archive' or 'Archives' (case insensitive)
archive_found = False
archive_count = 0
archive_name = ""

for entry in os.listdir(MAILDIR):
    if entry.startswith('.'):
        folder_name = entry[1:] # Remove dot
        if folder_name.lower() in ['archive', 'archives']:
            archive_found = True
            archive_name = folder_name
            archive_emails = get_emails_in_folder(os.path.join(MAILDIR, entry))
            archive_count = len(archive_emails)
            break

# 4. Analyze Drafts and Sent (for notification email)
drafts = []
sent = []

drafts_path = os.path.join(MAILDIR, ".Drafts")
for f in get_emails_in_folder(drafts_path):
    if os.path.getmtime(f) > TASK_START:
        drafts.append(parse_email_content(f))

sent_path = os.path.join(MAILDIR, ".Sent")
for f in get_emails_in_folder(sent_path):
    if os.path.getmtime(f) > TASK_START:
        sent.append(parse_email_content(f))

# 5. Inbox State
inbox_emails = get_emails_in_folder(MAILDIR) # Root Maildir is Inbox
inbox_count = len(inbox_emails)

result = {
    "flagged_count": flagged_count,
    "trash_count": trash_count,
    "trash_moved_during_task": trash_new_count,
    "archive_folder_exists": archive_found,
    "archive_folder_name": archive_name,
    "archive_email_count": archive_count,
    "inbox_count": inbox_count,
    "drafts": drafts,
    "sent": sent,
    "timestamp": TASK_START
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Clean up permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="