#!/bin/bash
echo "=== Exporting patch_contribution_harvesting result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task timings
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# Analyze Maildir State
# ============================================================
MAILDIR="/home/ga/Maildir"
TARGET_FOLDER_NAME="Patch-Review"
TARGET_DIR=""

# Find the specific folder (handle case sensitivity if needed, though task says exact name)
# BlueMail creates folders as .FolderName
if [ -d "${MAILDIR}/.${TARGET_FOLDER_NAME}" ]; then
    TARGET_DIR="${MAILDIR}/.${TARGET_FOLDER_NAME}"
elif [ -d "${MAILDIR}/.patch-review" ]; then
    TARGET_DIR="${MAILDIR}/.patch-review"
fi

FOLDER_EXISTS="false"
EMAIL_COUNT=0
VALID_PATCH_COUNT=0

if [ -n "$TARGET_DIR" ]; then
    FOLDER_EXISTS="true"
    
    # Count total emails in folder
    EMAIL_COUNT=$(find "${TARGET_DIR}/cur" "${TARGET_DIR}/new" -type f 2>/dev/null | wc -l)
    
    # Analyze content for patch markers
    # We look for diff headers or [PATCH] subject
    # Use python for safer parsing/matching
    VALID_PATCH_COUNT=$(python3 << 'PYEOF'
import os
import re

target_dir = os.environ.get('TARGET_DIR')
count = 0
if target_dir and os.path.exists(target_dir):
    for subdir in ['cur', 'new']:
        path = os.path.join(target_dir, subdir)
        if not os.path.exists(path): continue
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if os.path.isfile(fpath):
                try:
                    with open(fpath, 'r', errors='ignore') as f:
                        content = f.read()
                        # Simple heuristics for patch content
                        if (re.search(r'^diff -u', content, re.MULTILINE) or
                            re.search(r'^Index:', content, re.MULTILINE) or
                            (re.search(r'^--- ', content, re.MULTILINE) and re.search(r'^\+\+\+ ', content, re.MULTILINE)) or
                            re.search(r'Subject:.*\[PATCH\]', content, re.IGNORECASE)):
                            count += 1
                except:
                    pass
print(count)
PYEOF
)
fi

# Analyze Inbox count
INBOX_COUNT=$(find "${MAILDIR}/cur" "${MAILDIR}/new" -type f 2>/dev/null | wc -l)

# Analyze Drafts/Sent for report
REPORT_FOUND="false"
REPORT_RECIPIENT=""
REPORT_SUBJECT=""

python3 << 'PYEOF' > /tmp/report_analysis.json
import os
import json
import re

maildir = "/home/ga/Maildir"
report_found = False
recipient = ""
subject = ""

# Check both Drafts and Sent
for folder in ['.Drafts', '.Sent']:
    path = os.path.join(maildir, folder)
    for subdir in ['cur', 'new']:
        subpath = os.path.join(path, subdir)
        if not os.path.exists(subpath): continue
        
        # Check files modified after task start
        # (Simplified: just check all, verifier checks logic)
        for fname in os.listdir(subpath):
            fpath = os.path.join(subpath, fname)
            if not os.path.isfile(fpath): continue
            
            try:
                with open(fpath, 'r', errors='ignore') as f:
                    content = f.read()
                    
                # Extract headers
                to_match = re.search(r'^To:\s*(.*)', content, re.MULTILINE | re.IGNORECASE)
                sub_match = re.search(r'^Subject:\s*(.*)', content, re.MULTILINE | re.IGNORECASE)
                
                curr_to = to_match.group(1).strip() if to_match else ""
                curr_sub = sub_match.group(1).strip() if sub_match else ""
                
                if "lead-dev@project.org" in curr_to:
                    report_found = True
                    recipient = curr_to
                    subject = curr_sub
                    break
            except:
                continue
        if report_found: break
    if report_found: break

print(json.dumps({
    "found": report_found,
    "recipient": recipient,
    "subject": subject
}))
PYEOF

# Merge python analysis
REPORT_JSON=$(cat /tmp/report_analysis.json)

# Check app state
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "folder_exists": $FOLDER_EXISTS,
    "folder_email_count": $EMAIL_COUNT,
    "valid_patch_count": $VALID_PATCH_COUNT,
    "inbox_count": $INBOX_COUNT,
    "report_email": $REPORT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="