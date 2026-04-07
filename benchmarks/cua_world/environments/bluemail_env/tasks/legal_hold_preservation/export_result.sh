#!/bin/bash
echo "=== Exporting legal_hold_preservation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# ANALYZE RESULTS WITH PYTHON
# ============================================================
# We analyze the "Legal-Hold-2024" folder to see:
# 1. How many emails are in there?
# 2. Do they contain the keywords? (Precision)
# 3. Were they moved from Junk? (Origin tracking via filename tags we added in setup)

python3 << 'PYEOF'
import os
import json
import re

MAILDIR = "/home/ga/Maildir"
TARGET_FOLDER_NAME = "Legal-Hold-2024"
KEYWORDS = ["license", "copyright", "patent", "GPL"]

result = {
    "folder_exists": False,
    "folder_email_count": 0,
    "true_positives": 0,
    "false_positives": 0,
    "junk_source_preserved": 0,
    "drafts": [],
    "sent": []
}

# 1. Locate the legal hold folder
target_path = None
for entry in os.listdir(MAILDIR):
    if entry.startswith(".") and entry[1:].lower() == TARGET_FOLDER_NAME.lower():
        target_path = os.path.join(MAILDIR, entry)
        result["folder_exists"] = True
        break

# 2. Analyze preserved emails
if target_path:
    for subdir in ["cur", "new"]:
        dpath = os.path.join(target_path, subdir)
        if os.path.exists(dpath):
            for fname in os.listdir(dpath):
                fpath = os.path.join(dpath, fname)
                if not os.path.isfile(fpath): continue
                
                result["folder_email_count"] += 1
                
                # Check Content (Is it a True Positive?)
                try:
                    with open(fpath, 'r', errors='ignore') as f:
                        content = f.read().lower()
                    
                    if any(k.lower() in content for k in KEYWORDS):
                        result["true_positives"] += 1
                    else:
                        result["false_positives"] += 1
                        
                    # Check Origin (Was it from Spam?)
                    # Setup script tagged files with .spam.ga or .ham.ga
                    if ".spam.ga" in fname:
                        result["junk_source_preserved"] += 1
                        
                except Exception:
                    pass

# 3. Parse Drafts/Sent for Certification Email
def parse_email(fpath):
    try:
        with open(fpath, 'r', errors='ignore') as f:
            raw = f.read()
        
        # Simple header parsing
        headers = {}
        body = ""
        in_body = False
        
        for line in raw.split('\n'):
            if in_body:
                body += line + "\n"
                continue
            if line.strip() == "":
                in_body = True
                continue
            
            m = re.match(r'^([\w-]+):\s*(.*)', line)
            if m:
                headers[m.group(1).lower()] = m.group(2).strip()
                
        return {
            "to": headers.get("to", ""),
            "subject": headers.get("subject", ""),
            "body": body.lower()[:2000] # Limit body size
        }
    except:
        return None

for folder in [".Drafts", ".Sent"]:
    for subdir in ["cur", "new"]:
        path = os.path.join(MAILDIR, folder, subdir)
        if os.path.exists(path):
            for fname in os.listdir(path):
                data = parse_email(os.path.join(path, fname))
                if data:
                    if folder == ".Drafts":
                        result["drafts"].append(data)
                    else:
                        result["sent"].append(data)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="