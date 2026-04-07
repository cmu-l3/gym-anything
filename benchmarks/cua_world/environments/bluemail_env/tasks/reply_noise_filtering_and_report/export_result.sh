#!/bin/bash
echo "=== Exporting reply_noise_filtering results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
MAILDIR="/home/ga/Maildir"
ARCHIVE_DIR="${MAILDIR}/.Replies-Archive"
INBOX_DIR="${MAILDIR}/cur"
SENT_DIR="${MAILDIR}/.Sent/cur"

# Ensure dirs exist for listing
mkdir -p "$INBOX_DIR" "$SENT_DIR"

# Python script to analyze the Maildir state accurately
# It checks:
# 1. Archive folder existence and content (Precision/Recall of "Re:" moves)
# 2. Inbox content (Should be clean of "Re:")
# 3. Inbox flags (Should have 'F' flag)
# 4. Sent folder (Should have report with correct count)

python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy
from email.parser import BytesParser

maildir = "/home/ga/Maildir"
archive_dir = os.path.join(maildir, ".Replies-Archive")
inbox_dirs = [os.path.join(maildir, "cur"), os.path.join(maildir, "new")]
sent_dirs = [os.path.join(maildir, ".Sent", "cur"), os.path.join(maildir, ".Sent", "new")]

result = {
    "archive_exists": False,
    "archive_count": 0,
    "archive_re_count": 0,    # How many in archive actually have Re:
    "archive_bad_count": 0,   # How many in archive do NOT have Re:
    "inbox_count": 0,
    "inbox_re_count": 0,      # How many left in inbox still have Re: (missed)
    "inbox_clean_count": 0,   # How many in inbox are correct (no Re:)
    "inbox_flagged_count": 0, # How many in inbox are flagged
    "report_found": False,
    "report_extracted_count": None,
    "timestamp": 0
}

# Helper to check subject
def is_reply(subject):
    if not subject: return False
    return subject.lower().strip().startswith("re:")

# 1. Check Archive
if os.path.isdir(archive_dir):
    result["archive_exists"] = True
    for subdir in ["cur", "new"]:
        d = os.path.join(archive_dir, subdir)
        if os.path.exists(d):
            for fname in os.listdir(d):
                fpath = os.path.join(d, fname)
                if os.path.isfile(fpath):
                    result["archive_count"] += 1
                    with open(fpath, 'rb') as f:
                        msg = BytesParser(policy=policy.default).parse(f)
                    if is_reply(msg['subject']):
                        result["archive_re_count"] += 1
                    else:
                        result["archive_bad_count"] += 1

# 2. Check Inbox
for d in inbox_dirs:
    if os.path.exists(d):
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                result["inbox_count"] += 1
                
                # Check flag in filename (Dovecot maildir format: ...:2,FS or ...:2,S...)
                # Look for 'F' in the flags section after comma
                flags = ""
                if "," in fname:
                    flags = fname.split(",")[-1]
                if "F" in flags:
                    result["inbox_flagged_count"] += 1
                
                # Check content
                with open(fpath, 'rb') as f:
                    msg = BytesParser(policy=policy.default).parse(f)
                if is_reply(msg['subject']):
                    result["inbox_re_count"] += 1
                else:
                    result["inbox_clean_count"] += 1

# 3. Check Report in Sent
report_candidates = []
for d in sent_dirs:
    if os.path.exists(d):
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                with open(fpath, 'rb') as f:
                    msg = BytesParser(policy=policy.default).parse(f)
                
                to_addr = msg['to'] or ""
                subject = msg['subject'] or ""
                
                if "manager@company.com" in to_addr:
                    # Extract body
                    body = ""
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_type() == "text/plain":
                                body = part.get_content()
                                break
                    else:
                        body = msg.get_content()
                    
                    # Look for a number in the body
                    nums = re.findall(r'\b\d+\b', body)
                    if nums:
                        result["report_found"] = True
                        result["report_extracted_count"] = int(nums[0]) # Take first number found
                        break

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# Clean up permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="