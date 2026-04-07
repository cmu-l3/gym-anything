#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze the state of the Maildir using Python
# This script calculates score metrics inside the environment
python3 << 'PYEOF'
import os
import json
import re
import email.utils
from email import message_from_file

MAILDIR = "/home/ga/Maildir"
TASK_START = int(open('/tmp/task_start_time.txt').read().strip())
GROUND_TRUTH_FILE = '/tmp/ground_truth_distribution.json'

result = {
    "folders_created": [],
    "total_emails_moved": 0,
    "correctly_sorted": 0,
    "sorting_accuracy": 0.0,
    "draft_report_found": False,
    "sent_report_found": False,
    "report_details": {},
    "inbox_remaining": 0
}

# Load ground truth if available (for reference, though we re-parse to be safe)
ground_truth = {}
if os.path.exists(GROUND_TRUTH_FILE):
    with open(GROUND_TRUTH_FILE) as f:
        ground_truth = json.load(f)

# 1. Analyze Folders
folder_pattern = re.compile(r'^\.(Archive-\d{4}-\d{2})$', re.IGNORECASE)
archive_folders = []

try:
    all_dirs = os.listdir(MAILDIR)
    for d in all_dirs:
        match = folder_pattern.match(d)
        if match:
            folder_name = match.group(1)
            folder_path = os.path.join(MAILDIR, d)
            
            # Count emails in cur/ and new/
            emails = []
            for sub in ['cur', 'new']:
                p = os.path.join(folder_path, sub)
                if os.path.exists(p):
                    emails.extend([os.path.join(p, f) for f in os.listdir(p) if os.path.isfile(os.path.join(p, f))])
            
            # Check date accuracy
            folder_correct = 0
            folder_total = len(emails)
            
            # Extract target YYYY-MM from folder name (e.g., Archive-2002-08 -> 2002-08)
            target_date_str = re.search(r'(\d{4}-\d{2})', folder_name).group(1)
            
            for eml_path in emails:
                try:
                    with open(eml_path, 'r', encoding='latin1', errors='ignore') as f:
                        msg = message_from_file(f)
                    
                    dt = email.utils.parsedate_to_datetime(msg.get('Date'))
                    if dt:
                        eml_ym = f"{dt.year}-{dt.month:02d}"
                        if eml_ym == target_date_str:
                            folder_correct += 1
                except:
                    pass
            
            archive_folders.append({
                "name": folder_name,
                "count": folder_total,
                "correct": folder_correct
            })
            
            result["total_emails_moved"] += folder_total
            result["correctly_sorted"] += folder_correct

    result["folders_created"] = archive_folders
    
    if result["total_emails_moved"] > 0:
        result["sorting_accuracy"] = (result["correctly_sorted"] / result["total_emails_moved"]) * 100

    # 2. Check Inbox Remaining
    inbox_count = 0
    for sub in ['cur', 'new']:
        p = os.path.join(MAILDIR, sub)
        if os.path.exists(p):
            inbox_count += len([f for f in os.listdir(p) if os.path.isfile(os.path.join(p, f))])
    result["inbox_remaining"] = inbox_count

    # 3. Check for Report (Draft or Sent)
    target_recipient = "records@techcorp.com"
    
    def check_report(folder_path):
        found = False
        details = {}
        if not os.path.exists(folder_path):
            return False, {}
            
        # Check files modified/created after task start
        for sub in ['cur', 'new']:
            p = os.path.join(folder_path, sub)
            if not os.path.exists(p):
                continue
                
            for fname in os.listdir(p):
                fpath = os.path.join(p, fname)
                try:
                    mtime = os.path.getmtime(fpath)
                    if mtime > TASK_START:
                        with open(fpath, 'r', encoding='latin1', errors='ignore') as f:
                            content = f.read()
                            # Simple string check for headers to avoid parsing complexity issues
                            if f"To: {target_recipient}" in content or f"To: <{target_recipient}>" in content:
                                found = True
                                msg = message_from_string(content)
                                details = {
                                    "subject": msg.get('Subject', ''),
                                    "body_snippet": content[:1000] # Grab raw content for verification
                                }
                                return True, details
                except:
                    continue
        return False, {}

    # Need to import message_from_string locally or reuse
    from email import message_from_string

    is_draft, draft_details = check_report(os.path.join(MAILDIR, ".Drafts"))
    if is_draft:
        result["draft_report_found"] = True
        result["report_details"] = draft_details

    is_sent, sent_details = check_report(os.path.join(MAILDIR, ".Sent"))
    if is_sent:
        result["sent_report_found"] = True
        result["report_details"] = sent_details

except Exception as e:
    result["error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="