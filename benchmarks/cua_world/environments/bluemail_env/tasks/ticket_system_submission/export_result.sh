#!/bin/bash
echo "=== Exporting ticket_system_submission results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check BlueMail status
BM_RUNNING=$(is_bluemail_running && echo "true" || echo "false")

# ============================================================
# Python script to analyze Maildir state
# ============================================================
python3 << 'PYEOF'
import os
import json
import re
import email
from email.parser import BytesParser
from email import policy

MAILDIR = "/home/ga/Maildir"
TASK_START = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

result = {
    "task_start": TASK_START,
    "app_running": False,
    "sent_email_found": False,
    "sent_email_data": None,
    "archive_folder_exists": False,
    "archived_email_count": 0,
    "archived_email_subjects": []
}

# 1. Analyze Sent Emails (Sent or Drafts/Outbox if failing)
# We look for the most recent email sent to tickets@localhost
sent_dirs = [
    f"{MAILDIR}/.Sent/cur", f"{MAILDIR}/.Sent/new",
    f"{MAILDIR}/.Drafts/cur", f"{MAILDIR}/.Drafts/new" # Fallback if agent saved as draft
]

candidates = []

for d in sent_dirs:
    if not os.path.isdir(d):
        continue
    for fname in os.listdir(d):
        fpath = os.path.join(d, fname)
        try:
            mtime = os.path.getmtime(fpath)
            if mtime > TASK_START:
                with open(fpath, 'rb') as f:
                    msg = BytesParser(policy=policy.default).parse(f)
                    
                to_addr = msg.get('To', '').lower()
                subject = msg.get('Subject', '')
                
                # Get body
                body = ""
                if msg.is_multipart():
                    for part in msg.walk():
                        if part.get_content_type() == "text/plain":
                            body = part.get_content()
                            break
                else:
                    body = msg.get_content()

                candidates.append({
                    "mtime": mtime,
                    "to": to_addr,
                    "subject": subject,
                    "body_start": body.strip()[:200], # First 200 chars
                    "path": fpath
                })
        except Exception as e:
            continue

# Sort by time, newest first
candidates.sort(key=lambda x: x['mtime'], reverse=True)

# Find the best match for the task
for cand in candidates:
    if "tickets@localhost" in cand['to']:
        result["sent_email_found"] = True
        result["sent_email_data"] = cand
        break

# 2. Analyze Archive Folder (Processed-Tickets)
# Check exact name "Processed-Tickets" or case variants
archive_path = None
for entry in os.listdir(MAILDIR):
    if entry.lower() == ".processed-tickets":
        archive_path = os.path.join(MAILDIR, entry)
        result["archive_folder_exists"] = True
        break

if archive_path:
    count = 0
    subjects = []
    for subdir in ["cur", "new"]:
        sp = os.path.join(archive_path, subdir)
        if os.path.isdir(sp):
            for fname in os.listdir(sp):
                fpath = os.path.join(sp, fname)
                count += 1
                try:
                    with open(fpath, 'rb') as f:
                        msg = BytesParser(policy=policy.default).parse(f)
                    subjects.append(msg.get('Subject', 'No Subject'))
                except:
                    pass
    result["archived_email_count"] = count
    result["archived_email_subjects"] = subjects

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure result file exists
if [ ! -f /tmp/task_result.json ]; then
    echo "{}" > /tmp/task_result.json
fi

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="