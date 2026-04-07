#!/bin/bash
echo "=== Exporting Critical Bug Thread Isolation Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Parameters
MAILDIR="/home/ga/Maildir"

# Export data using Python
python3 << PYEOF
import os
import json
import re
import glob

MAILDIR = "$MAILDIR"
GROUND_TRUTH_FILE = "/tmp/task_ground_truth.json"

result = {
    "timestamp": os.popen("date -Iseconds").read().strip(),
    "critical_folder_exists": False,
    "critical_folder_count": 0,
    "critical_folder_emails": [],
    "inbox_bug_emails": [],
    "draft_email": None
}

# 1. Load Ground Truth
try:
    with open(GROUND_TRUTH_FILE, 'r') as f:
        ground_truth = json.load(f)
        result["ground_truth"] = ground_truth
except Exception as e:
    result["error"] = f"Failed to load ground truth: {e}"

# 2. Inspect Critical-Thread Folder
# BlueMail creates folders as .FolderName in Maildir
folder_path = os.path.join(MAILDIR, ".Critical-Thread", "cur")
if os.path.isdir(folder_path):
    result["critical_folder_exists"] = True
    
    files = glob.glob(os.path.join(folder_path, "*"))
    result["critical_folder_count"] = len(files)
    
    # Analyze headers of moved emails
    for fpath in files:
        try:
            with open(fpath, 'r', errors='ignore') as f:
                content = f.read(2048) # Read header area
                
            # Simple regex extract subject
            subject_match = re.search(r'^Subject: (.*)$', content, re.MULTILINE | re.IGNORECASE)
            subject = subject_match.group(1).strip() if subject_match else "No Subject"
            
            result["critical_folder_emails"].append({
                "subject": subject
            })
        except:
            pass
else:
    # Try case variants
    for d in glob.glob(os.path.join(MAILDIR, ".*")):
        if "critical" in d.lower() and "thread" in d.lower():
            result["found_folder_variant"] = d

# 3. Inspect Inbox (to check if bugs were left behind)
inbox_path = os.path.join(MAILDIR, "cur")
if os.path.isdir(inbox_path):
    files = glob.glob(os.path.join(inbox_path, "*"))
    for fpath in files:
        try:
            with open(fpath, 'r', errors='ignore') as f:
                content = f.read(2048)
            
            if "Bug" in content and "Subject:" in content:
                 subject_match = re.search(r'^Subject: (.*)$', content, re.MULTILINE | re.IGNORECASE)
                 subject = subject_match.group(1).strip() if subject_match else ""
                 
                 # Look for Bug ID pattern
                 bug_match = re.search(r'Bug\s*(\d+)', subject, re.IGNORECASE)
                 if bug_match:
                     result["inbox_bug_emails"].append({
                         "id": bug_match.group(1),
                         "subject": subject
                     })
        except:
            pass

# 4. Inspect Drafts
drafts_path = os.path.join(MAILDIR, ".Drafts", "cur")
if os.path.isdir(drafts_path):
    files = glob.glob(os.path.join(drafts_path, "*"))
    # Get latest draft
    if files:
        latest_file = max(files, key=os.path.getctime)
        with open(latest_file, 'r', errors='ignore') as f:
            content = f.read()
            
        # Parse minimal headers
        to_match = re.search(r'^To: (.*)$', content, re.MULTILINE | re.IGNORECASE)
        sub_match = re.search(r'^Subject: (.*)$', content, re.MULTILINE | re.IGNORECASE)
        
        # Body is everything after first blank line
        body = ""
        parts = content.split('\n\n', 1)
        if len(parts) > 1:
            body = parts[1][:1000] # Cap body length
            
        result["draft_email"] = {
            "to": to_match.group(1).strip() if to_match else "",
            "subject": sub_match.group(1).strip() if sub_match else "",
            "body": body
        }

# Save Result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="