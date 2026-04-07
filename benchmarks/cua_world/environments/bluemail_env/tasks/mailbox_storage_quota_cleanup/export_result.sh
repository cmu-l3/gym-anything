#!/bin/bash
# Export script for mailbox_storage_quota_cleanup
echo "=== Exporting results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png ga

# 2. Check BlueMail state
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# 3. Analyze Maildir Filesystem
MAILDIR="/home/ga/Maildir"

# Python script to analyze storage and content
python3 << 'PYEOF'
import os
import json
import glob

maildir = "/home/ga/Maildir"
large_subjects = [
    "Project Assets Backup 1",
    "Project Assets Backup 2",
    "High Res Dump",
    "Video Archive",
    "Log Dump 2023"
]

def get_dir_size(path):
    total = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if os.path.isfile(fp):
                total += os.path.getsize(fp)
    return total

def count_emails(path):
    if not os.path.exists(path): return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

def find_large_emails(path_pattern):
    found = []
    files = glob.glob(path_pattern)
    for f in files:
        if not os.path.isfile(f): continue
        try:
            # We only need to check headers, but large files might have header at top
            # Reading first 2KB is usually enough for headers
            with open(f, 'rb') as fp:
                content = fp.read(4096).decode('utf-8', errors='ignore')
                for subj in large_subjects:
                    if f"Subject: {subj}" in content:
                        found.append(subj)
        except Exception:
            pass
    return found

# 1. Calculate Total Size
total_size_bytes = get_dir_size(maildir)

# 2. Check Inbox for Normal Emails and Large Emails
inbox_cur = os.path.join(maildir, "cur")
inbox_new = os.path.join(maildir, "new")

inbox_files = glob.glob(os.path.join(inbox_cur, "*")) + glob.glob(os.path.join(inbox_new, "*"))
inbox_count = len(inbox_files)

# Identify remaining large emails in Inbox
remaining_large_inbox = find_large_emails(os.path.join(maildir, "*", "*")) # Check everywhere initially
# Narrow down to Inbox specifically
remaining_large_in_inbox = []
for f in inbox_files:
    try:
        with open(f, 'rb') as fp:
            content = fp.read(4096).decode('utf-8', errors='ignore')
            for subj in large_subjects:
                if f"Subject: {subj}" in content:
                    remaining_large_in_inbox.append(subj)
    except: pass

# 3. Check Trash
trash_cur = os.path.join(maildir, ".Trash", "cur")
trash_new = os.path.join(maildir, ".Trash", "new")
trash_count = count_emails(trash_cur) + count_emails(trash_new)

# Identify large emails in Trash (did they delete but not empty?)
trash_files = glob.glob(os.path.join(trash_cur, "*")) + glob.glob(os.path.join(trash_new, "*"))
remaining_large_in_trash = []
for f in trash_files:
    try:
        with open(f, 'rb') as fp:
            content = fp.read(4096).decode('utf-8', errors='ignore')
            for subj in large_subjects:
                if f"Subject: {subj}" in content:
                    remaining_large_in_trash.append(subj)
    except: pass

# 4. Construct Result
result = {
    "final_maildir_size_bytes": total_size_bytes,
    "inbox_email_count": inbox_count,
    "trash_item_count": trash_count,
    "remaining_large_in_inbox": list(set(remaining_large_in_inbox)),
    "remaining_large_in_trash": list(set(remaining_large_in_trash)),
    "large_emails_totally_gone": (len(remaining_large_in_inbox) == 0 and len(remaining_large_in_trash) == 0),
    "bluemail_running": os.system("pgrep -f bluemail > /dev/null") == 0
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json