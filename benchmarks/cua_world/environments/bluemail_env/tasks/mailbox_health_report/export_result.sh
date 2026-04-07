#!/bin/bash
echo "=== Exporting mailbox_health_report result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/mailbox_health_report.txt"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze the Text Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE=0
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    # Read content (limit size to prevent huge JSONs)
    REPORT_CONTENT=$(head -c 4096 "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze Drafts/Sent emails for the summary
# We look for emails to 'ops-director@company.com'
python3 << 'PYEOF'
import os
import json
import email
from email import policy

target_email = "ops-director@company.com"
maildir_root = "/home/ga/Maildir"
found_emails = []

def scan_folder(folder_path):
    if not os.path.exists(folder_path):
        return
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path):
            continue
        for filename in os.listdir(path):
            filepath = os.path.join(path, filename)
            try:
                with open(filepath, 'rb') as f:
                    msg = email.message_from_binary_file(f, policy=policy.default)
                    
                to_addr = str(msg['to']).lower() if msg['to'] else ""
                if target_email in to_addr:
                    # Extract body
                    body = ""
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_type() == "text/plain":
                                body = part.get_content()
                                break
                    else:
                        body = msg.get_content()
                        
                    found_emails.append({
                        "subject": str(msg['subject']),
                        "to": to_addr,
                        "body": body,
                        "folder": folder_path
                    })
            except Exception as e:
                continue

# Scan Drafts and Sent
scan_folder(os.path.join(maildir_root, ".Drafts"))
scan_folder(os.path.join(maildir_root, ".Sent"))

with open("/tmp/found_emails.json", "w") as f:
    json.dump(found_emails, f)
PYEOF

# 4. Get Actual Final Counts (Ground Truth at End)
# (Same logic as setup, ensuring we check current state)
python3 << 'PYEOF'
import os
import json

maildir_root = "/home/ga/Maildir"
def count_folder(path):
    if not os.path.exists(path): return 0
    return len([f for f in os.listdir(os.path.join(path, 'cur')) if os.path.isfile(os.path.join(path, 'cur', f))]) + \
           len([f for f in os.listdir(os.path.join(path, 'new')) if os.path.isfile(os.path.join(path, 'new', f))])

final_counts = {
    "inbox": count_folder(maildir_root),
    "junk": count_folder(os.path.join(maildir_root, ".Junk")),
    "drafts": count_folder(os.path.join(maildir_root, ".Drafts")),
    "sent": count_folder(os.path.join(maildir_root, ".Sent")),
    "trash": count_folder(os.path.join(maildir_root, ".Trash"))
}
with open("/tmp/final_counts.json", "w") as f:
    json.dump(final_counts, f)
PYEOF

# 5. Assemble Final JSON
FOUND_EMAILS_JSON=$(cat /tmp/found_emails.json)
FINAL_COUNTS_JSON=$(cat /tmp/final_counts.json)
INITIAL_COUNTS_JSON=$(cat /tmp/initial_counts.json 2>/dev/null || echo "{}")

# Escape content for JSON inclusion using Python to avoid bash escaping hell
python3 -c "
import json
import sys

output = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'report_exists': $REPORT_EXISTS,
    'report_created_during_task': $REPORT_CREATED_DURING_TASK,
    'report_size': $REPORT_SIZE,
    'report_content': sys.stdin.read(),
    'found_emails': $FOUND_EMAILS_JSON,
    'final_counts': $FINAL_COUNTS_JSON,
    'initial_counts': $INITIAL_COUNTS_JSON,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(output))
" <<< "$REPORT_CONTENT" > /tmp/task_result.json

# Cleanup permissions
chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"