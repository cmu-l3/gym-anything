#!/bin/bash
echo "=== Exporting Knowledge Base Extraction Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/kb_task_end.png

# 2. Python script to analyze Maildir, Index File, and Drafts
python3 << 'PYEOF'
import os
import json
import re
import time

MAILDIR = "/home/ga/Maildir"
DOCS_DIR = "/home/ga/Documents"
INDEX_FILE = os.path.join(DOCS_DIR, "kb_index.txt")
TASK_START_FILE = "/tmp/task_start_time"

result = {
    "timestamp": time.time(),
    "kb_folders": {},
    "inbox_count": 0,
    "index_file": {
        "exists": False,
        "content": "",
        "valid_timestamp": False
    },
    "announcement_email": {
        "found": False,
        "recipient_match": False,
        "subject_match": False,
        "body_snippet": ""
    }
}

# --- Analyze Maildir ---
def count_emails(path):
    count = 0
    for subdir in ["cur", "new"]:
        d = os.path.join(path, subdir)
        if os.path.isdir(d):
            count += len([f for f in os.listdir(d) if os.path.isfile(os.path.join(d, f))])
    return count

# Count inbox
result["inbox_count"] = count_emails(MAILDIR)

# Find KB folders (case-insensitive search for KB-Security, etc.)
target_prefixes = ["kb-security", "kb-linux", "kb-development"]
for entry in os.listdir(MAILDIR):
    if not entry.startswith("."): continue
    
    folder_name = entry[1:] # Remove dot
    clean_name = folder_name.lower()
    
    # Check if this is one of our target KB folders
    # We allow loose matching (e.g. KB_Security, KB-Security)
    is_target = any(p in clean_name.replace("_", "-") for p in target_prefixes)
    
    if is_target:
        count = count_emails(os.path.join(MAILDIR, entry))
        result["kb_folders"][folder_name] = count

# --- Analyze Index File ---
if os.path.exists(INDEX_FILE):
    result["index_file"]["exists"] = True
    try:
        with open(INDEX_FILE, 'r') as f:
            result["index_file"]["content"] = f.read(2000) # Read first 2KB
        
        # Check timestamp
        task_start = 0
        if os.path.exists(TASK_START_FILE):
            with open(TASK_START_FILE, 'r') as f:
                task_start = int(f.read().strip())
        
        file_mtime = os.path.getmtime(INDEX_FILE)
        if file_mtime > task_start:
            result["index_file"]["valid_timestamp"] = True
            
    except Exception as e:
        result["index_file"]["error"] = str(e)

# --- Analyze Drafts/Sent for Announcement ---
def parse_eml(fpath):
    headers = {}
    body = ""
    try:
        with open(fpath, 'r', errors='ignore') as f:
            content = f.read()
            parts = content.split('\n\n', 1)
            header_block = parts[0]
            body = parts[1] if len(parts) > 1 else ""
            
            for line in header_block.split('\n'):
                if ':' in line:
                    key, val = line.split(':', 1)
                    headers[key.strip().lower()] = val.strip()
    except:
        pass
    return headers, body

target_email = "it-team@company.com"
candidates = []

# Scan Sent and Drafts
for folder in [".Sent", ".Drafts"]:
    for subdir in ["cur", "new"]:
        path = os.path.join(MAILDIR, folder, subdir)
        if os.path.isdir(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                if os.path.isfile(fpath):
                    # Check mtime
                    if os.path.getmtime(fpath) > (time.time() - 3600): # Recent only
                        headers, body = parse_eml(fpath)
                        candidates.append({"headers": headers, "body": body})

# Check candidates against criteria
for email in candidates:
    to = email["headers"].get("to", "")
    subject = email["headers"].get("subject", "")
    
    if target_email in to:
        result["announcement_email"]["found"] = True
        result["announcement_email"]["recipient_match"] = True
        result["announcement_email"]["body_snippet"] = email["body"][:200]
        
        if "knowledge" in subject.lower() or "kb" in subject.lower():
            result["announcement_email"]["subject_match"] = True
        break

# Dump result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# 3. Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json