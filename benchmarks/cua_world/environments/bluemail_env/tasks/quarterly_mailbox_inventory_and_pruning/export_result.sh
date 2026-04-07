#!/bin/bash
set -e
echo "=== Exporting quarterly_mailbox_inventory_and_pruning results ==="

source /workspace/scripts/task_utils.sh

MAILDIR="/home/ga/Maildir"
RESULT_FILE="/tmp/task_result.json"

# Record task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check BlueMail status
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# ============================================================
# Count emails in all folders
# ============================================================
count_folder() {
    local folder_path="$1"
    local count=0
    if [ -d "$folder_path/cur" ]; then
        count=$((count + $(ls -1 "$folder_path/cur/" 2>/dev/null | wc -l)))
    fi
    if [ -d "$folder_path/new" ]; then
        count=$((count + $(ls -1 "$folder_path/new/" 2>/dev/null | wc -l)))
    fi
    echo "$count"
}

INBOX_COUNT=$(count_folder "$MAILDIR")
JUNK_COUNT=$(count_folder "$MAILDIR/.Junk")
DRAFTS_COUNT=$(count_folder "$MAILDIR/.Drafts")
SENT_COUNT=$(count_folder "$MAILDIR/.Sent")
TRASH_COUNT=$(count_folder "$MAILDIR/.Trash")

# ============================================================
# Detect custom folders and Archive specifically
# ============================================================
# Use Python to handle JSON generation and fuzzy matching reliably
python3 << PYEOF
import os
import json
import re

maildir = "$MAILDIR"
default_folders = {'.Junk', '.Drafts', '.Sent', '.Trash', '.', '..'}
custom_folders = {}
archive_info = {
    "exists": False,
    "name": "",
    "count": 0,
    "is_match": False
}

# Scan Maildir for custom folders (dirs starting with .)
try:
    entries = os.listdir(maildir)
    for entry in entries:
        if not entry.startswith('.'): continue
        if entry in default_folders: continue
        
        full_path = os.path.join(maildir, entry)
        if not os.path.isdir(full_path): continue
        
        # Count emails
        cur_count = len([f for f in os.listdir(os.path.join(full_path, 'cur')) if os.path.isfile(os.path.join(full_path, 'cur', f))]) if os.path.exists(os.path.join(full_path, 'cur')) else 0
        new_count = len([f for f in os.listdir(os.path.join(full_path, 'new')) if os.path.isfile(os.path.join(full_path, 'new', f))]) if os.path.exists(os.path.join(full_path, 'new')) else 0
        total = cur_count + new_count
        
        folder_name = entry[1:] # Remove leading dot
        custom_folders[folder_name] = total
        
        # Check for archive match
        # Match "quarterly", "archive", "q4" roughly
        lower_name = folder_name.lower()
        if "archive" in lower_name and ("quarterly" in lower_name or "q4" in lower_name):
            archive_info["exists"] = True
            archive_info["name"] = folder_name
            archive_info["count"] = total
            archive_info["is_match"] = True

except Exception as e:
    print(f"Error scanning folders: {e}")

# Parse Drafts/Sent for report
def parse_emails(folder_path):
    emails = []
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path): continue
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if not os.path.isfile(fpath): continue
            try:
                with open(fpath, 'r', errors='ignore') as f:
                    content = f.read()
                    
                # Simple extraction
                to_match = re.search(r'^To: (.*)', content, re.M | re.I)
                subj_match = re.search(r'^Subject: (.*)', content, re.M | re.I)
                
                # Extract body (skip headers)
                body = ""
                parts = content.split('\n\n', 1)
                if len(parts) > 1:
                    body = parts[1][:1000] # First 1000 chars
                
                emails.append({
                    "to": to_match.group(1).strip() if to_match else "",
                    "subject": subj_match.group(1).strip() if subj_match else "",
                    "body": body
                })
            except:
                continue
    return emails

drafts = parse_emails(os.path.join(maildir, '.Drafts'))
sent = parse_emails(os.path.join(maildir, '.Sent'))

# Output JSON
result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "bluemail_running": "$BM_RUNNING" == "true",
    "inbox_count": $INBOX_COUNT,
    "junk_count": $JUNK_COUNT,
    "drafts_count": $DRAFTS_COUNT,
    "sent_count": $SENT_COUNT,
    "trash_count": $TRASH_COUNT,
    "custom_folders": custom_folders,
    "archive_folder": archive_info,
    "drafts": drafts,
    "sent": sent,
    "screenshot_path": "/tmp/task_final.png"
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="