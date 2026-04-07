#!/bin/bash
# Export script for priority_flagging_and_digest task
echo "=== Exporting priority_flagging_and_digest result ==="

source /workspace/scripts/task_utils.sh

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Verify Application State
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# 3. Force Dovecot sync (flush in-memory state to disk if needed)
doveadm force-resync -u ga INBOX 2>/dev/null || true

# 4. Python Analysis of Maildir
# We use Python to robustly parse email headers, flags, and folder structures
python3 << 'PYEOF'
import os
import json
import re
import glob

MAILDIR = "/home/ga/Maildir"
TASK_START = 0
try:
    with open('/tmp/task_start_time', 'r') as f:
        TASK_START = int(f.read().strip())
except:
    pass

def count_emails(path):
    if not os.path.exists(path): return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

def get_flagged_count(path):
    """Count files with 'F' in the suffix (e.g., :2,FS)"""
    if not os.path.exists(path): return 0
    count = 0
    for fname in os.listdir(path):
        if os.path.isfile(os.path.join(path, fname)):
            # Check for flag separator
            if ':2,' in fname:
                flags = fname.split(':2,')[1]
                if 'F' in flags:
                    count += 1
    return count

def parse_email_content(fpath):
    """Simple parser for To, Subject, Body"""
    try:
        with open(fpath, 'r', errors='ignore') as f:
            raw = f.read()
        
        # Split headers and body
        parts = raw.split('\n\n', 1)
        headers_raw = parts[0]
        body = parts[1] if len(parts) > 1 else ""
        
        headers = {}
        for line in headers_raw.split('\n'):
            if ':' in line:
                k, v = line.split(':', 1)
                headers[k.strip().lower()] = v.strip()
                
        return {
            "to": headers.get("to", ""),
            "subject": headers.get("subject", ""),
            "body": body[:2000] # Limit body size
        }
    except:
        return {"to": "", "subject": "", "body": ""}

# --- Data Collection ---

# 1. Inbox Analysis
inbox_total = count_emails(f"{MAILDIR}/cur") + count_emails(f"{MAILDIR}/new")
inbox_flagged = get_flagged_count(f"{MAILDIR}/cur") + get_flagged_count(f"{MAILDIR}/new")

# 2. Folder Analysis
priority_queue_exists = False
priority_queue_count = 0
custom_folders = {}

for entry in os.listdir(MAILDIR):
    if entry.startswith('.') and os.path.isdir(os.path.join(MAILDIR, entry)):
        folder_name = entry[1:] # Remove dot
        if folder_name in ['Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'Archive']:
            continue
            
        count = count_emails(f"{MAILDIR}/{entry}/cur") + count_emails(f"{MAILDIR}/{entry}/new")
        custom_folders[folder_name] = count
        
        # Check for target folder (flexible matching)
        clean_name = folder_name.lower().replace('-', '').replace('_', '').replace(' ', '')
        if 'priority' in clean_name and 'queue' in clean_name:
            priority_queue_exists = True
            priority_queue_count = count

# 3. Draft/Sent Analysis
digest_candidates = []
for folder in ['.Drafts', '.Sent']:
    for sub in ['cur', 'new']:
        path = f"{MAILDIR}/{folder}/{sub}"
        if os.path.exists(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                # Check modification time to ensure it wasn't pre-existing (anti-gaming)
                try:
                    mtime = os.path.getmtime(fpath)
                    if mtime > TASK_START:
                        data = parse_email_content(fpath)
                        data['folder'] = folder
                        digest_candidates.append(data)
                except:
                    pass

# Output JSON
result = {
    "inbox_count": inbox_total,
    "inbox_flagged_count": inbox_flagged,
    "priority_queue_exists": priority_queue_exists,
    "priority_queue_count": priority_queue_count,
    "custom_folders": custom_folders,
    "digest_emails": digest_candidates,
    "bluemail_running": True # Checked in bash
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Add bash-checked running state if python script failed to capture it correctly
# (Though the python script writes it as True hardcoded, we rely on the logic passing)
if [ "$BM_RUNNING" = "false" ]; then
    # Patch the json if app wasn't running
    sed -i 's/"bluemail_running": true/"bluemail_running": false/' /tmp/task_result.json
fi

# Read initial inbox count
INITIAL=$(cat /tmp/initial_inbox_count 2>/dev/null || echo "0")
# Add it to result using jq or sed? Let's just append a separate file and merge in verifier or just rely on verifier to know baseline
# Actually, let's append it to the JSON for convenience
sed -i "s/}/, \"initial_inbox_count\": $INITIAL }/" /tmp/task_result.json

echo "Result stored in /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="