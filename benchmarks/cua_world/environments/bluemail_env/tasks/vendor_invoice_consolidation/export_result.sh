#!/bin/bash
echo "=== Exporting vendor_invoice_consolidation result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# ============================================================
# Check Local Files (Downloads)
# ============================================================
TARGET_DIR="/home/ga/Documents/Invoices"
FILES_FOUND=0
FILES_DETAILS="[]"

if [ -d "$TARGET_DIR" ]; then
    # Use python to verify files and timestamps
    FILES_DETAILS=$(python3 << EOF
import os
import json
import glob

target_dir = "$TARGET_DIR"
task_start = $TASK_START
files_found = []
expected_files = ["acme_inv.csv", "beta_inv.csv", "gamma_inv.csv"]

for fname in expected_files:
    fpath = os.path.join(target_dir, fname)
    if os.path.exists(fpath):
        mtime = os.path.getmtime(fpath)
        size = os.path.getsize(fpath)
        # Verify it was created AFTER task start (anti-gaming)
        created_during_task = mtime > task_start
        files_found.append({
            "name": fname,
            "exists": True,
            "size": size,
            "created_during_task": created_during_task
        })

print(json.dumps(files_found))
EOF
    )
fi

# ============================================================
# Check Sent/Draft Emails (Consolidation)
# ============================================================
EMAIL_RESULT=$(python3 << 'EOF'
import os
import email
import json
import re

MAILDIR = "/home/ga/Maildir"
TARGET_RECIPIENT = "accounting@company.com"

# Check both Sent and Drafts
folders = [os.path.join(MAILDIR, '.Sent'), os.path.join(MAILDIR, '.Drafts')]
subdirs = ['cur', 'new']

best_match = {
    "found": False,
    "subject": "",
    "recipient": "",
    "attachment_count": 0,
    "attachment_names": []
}

found_emails = []

for folder in folders:
    if not os.path.exists(folder):
        continue
    for subdir in subdirs:
        path = os.path.join(folder, subdir)
        if not os.path.exists(path):
            continue
            
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if not os.path.isfile(fpath): 
                continue
                
            try:
                with open(fpath, 'rb') as f:
                    msg = email.message_from_binary_file(f)
                
                # Check recipient (simple check)
                to_header = msg.get('To', '').lower()
                if TARGET_RECIPIENT in to_header:
                    # Found a candidate
                    subject = msg.get('Subject', '')
                    attachments = []
                    
                    # Walk parts to find attachments
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_maintype() == 'multipart': continue
                            if part.get('Content-Disposition') is None: continue
                            
                            filename = part.get_filename()
                            if filename:
                                attachments.append(filename)
                    
                    match_data = {
                        "found": True,
                        "subject": subject,
                        "recipient": to_header,
                        "attachment_count": len(attachments),
                        "attachment_names": attachments,
                        "path": fpath
                    }
                    found_emails.append(match_data)
            except Exception as e:
                continue

# If multiple matches, find the best one (most attachments)
if found_emails:
    found_emails.sort(key=lambda x: x['attachment_count'], reverse=True)
    best_match = found_emails[0]

print(json.dumps(best_match))
EOF
)

# ============================================================
# Assemble Result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "target_dir_exists": $( [ -d "$TARGET_DIR" ] && echo "true" || echo "false" ),
    "downloaded_files": $FILES_DETAILS,
    "sent_email": $EMAIL_RESULT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="