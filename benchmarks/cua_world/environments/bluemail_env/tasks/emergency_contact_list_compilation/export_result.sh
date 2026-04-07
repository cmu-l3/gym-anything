#!/bin/bash
echo "=== Exporting Emergency Contact List Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# Python Script to Analyze Drafts and Inbox
# ============================================================
# We use Python to robustly parse the draft and verify against inbox
# This script runs INSIDE the container and produces the result JSON

python3 << 'PYEOF'
import os
import json
import re
import glob

MAILDIR = "/home/ga/Maildir"
DRAFT_DIRS = [f"{MAILDIR}/.Drafts/cur", f"{MAILDIR}/.Drafts/new"]
INBOX_DIRS = [f"{MAILDIR}/cur", f"{MAILDIR}/new"]

def extract_text_from_eml(filepath):
    """Simple text extraction from eml file."""
    try:
        with open(filepath, 'r', errors='ignore') as f:
            content = f.read()
            # Split headers and body (simplistic)
            parts = content.split('\n\n', 1)
            if len(parts) > 1:
                return parts[1], parts[0] # Body, Headers
            return content, ""
    except:
        return "", ""

def extract_headers(header_text):
    headers = {}
    for line in header_text.split('\n'):
        if ':' in line:
            key, val = line.split(':', 1)
            headers[key.strip().lower()] = val.strip()
    return headers

def find_phone_numbers(text):
    # Regex for 555-XXXX style numbers injected in setup
    # Also matches generic patterns just in case
    # Pattern: 555-XXXX or (XXX) XXX-XXXX
    return re.findall(r'555-\d{4}', text)

# 1. Find the latest draft
latest_draft = None
latest_mtime = 0
draft_content = ""
draft_headers = {}
draft_phones = []

for d_dir in DRAFT_DIRS:
    if not os.path.exists(d_dir): continue
    for fpath in glob.glob(f"{d_dir}/*"):
        mtime = os.path.getmtime(fpath)
        if mtime > latest_mtime:
            latest_mtime = mtime
            latest_draft = fpath

if latest_draft:
    body, header_text = extract_text_from_eml(latest_draft)
    draft_headers = extract_headers(header_text)
    draft_content = body
    draft_phones = find_phone_numbers(body)

# 2. Verify numbers exist in INBOX
verified_count = 0
verified_numbers = []

# Scan all inbox files
inbox_content = ""
for i_dir in INBOX_DIRS:
    if not os.path.exists(i_dir): continue
    for fpath in glob.glob(f"{i_dir}/*"):
        # Skip if it's the draft itself (unlikely in different dir)
        try:
            with open(fpath, 'r', errors='ignore') as f:
                inbox_content += f.read() + "\n"
        except: pass

for phone in set(draft_phones):
    if phone in inbox_content:
        verified_count += 1
        verified_numbers.append(phone)

# 3. Check BlueMail state
try:
    bm_running = os.system("pgrep -f bluemail > /dev/null") == 0
except:
    bm_running = False

result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "draft_found": latest_draft is not None,
    "draft_to": draft_headers.get('to', ''),
    "draft_subject": draft_headers.get('subject', ''),
    "draft_body_snippet": draft_content[:500],
    "extracted_phones_from_draft": draft_phones,
    "verified_phone_count": verified_count,
    "verified_numbers": verified_numbers,
    "app_running": bm_running
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export complete. Verified {verified_count} numbers.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export complete ==="