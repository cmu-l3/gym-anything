#!/bin/bash
# Export script for false_positive_rescue task
echo "=== Exporting false_positive_rescue result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Configuration
MAILDIR="/home/ga/Maildir"
GROUND_TRUTH_FILE="/tmp/false_positive_ids.txt"
EXPECTED_FOLDER="False-Positives"

# Python script to analyze results with high precision
python3 << 'PYEOF'
import os
import json
import re

maildir = "/home/ga/Maildir"
ground_truth_file = "/tmp/false_positive_ids.txt"
expected_folder_normalized = "false-positives"

# Helper to extract Message-ID
def get_message_id(filepath):
    try:
        with open(filepath, 'r', errors='ignore') as f:
            for line in f:
                if re.match(r'^Message-ID:', line, re.IGNORECASE):
                    return line.strip()
    except:
        pass
    return None

# Helper to parse email headers and body snippet
def parse_email_simple(filepath):
    try:
        headers = {}
        body_lines = []
        in_body = False
        with open(filepath, 'r', errors='ignore') as f:
            content = f.read(4096) # Read first 4KB
            
        lines = content.split('\n')
        for line in lines:
            if not in_body:
                if line.strip() == "":
                    in_body = True
                    continue
                match = re.match(r'^([\w-]+):\s*(.*)', line)
                if match:
                    headers[match.group(1).lower()] = match.group(2).strip()
            else:
                body_lines.append(line)
                if len(body_lines) > 20: break
        
        return {
            "to": headers.get("to", ""),
            "subject": headers.get("subject", ""),
            "body": " ".join(body_lines).lower()
        }
    except:
        return {}

# 1. Load Ground Truth Message-IDs
valid_fps = set()
if os.path.exists(ground_truth_file):
    with open(ground_truth_file, 'r') as f:
        valid_fps = {line.strip() for line in f if line.strip()}

# 2. Find the "False-Positives" folder (handle case variance)
target_folder_path = None
target_folder_name = ""

for entry in os.listdir(maildir):
    if not entry.startswith('.'): continue
    folder_name = entry[1:] # Remove dot
    if folder_name.lower().replace('_', '-') == expected_folder_normalized:
        target_folder_path = os.path.join(maildir, entry)
        target_folder_name = folder_name
        break

# 3. Analyze the target folder contents
rescued_count = 0
correct_rescues = 0
spam_rescues = 0

if target_folder_path:
    # Scan cur and new
    for subdir in ["cur", "new"]:
        dpath = os.path.join(target_folder_path, subdir)
        if os.path.exists(dpath):
            for fname in os.listdir(dpath):
                fpath = os.path.join(dpath, fname)
                if os.path.isfile(fpath):
                    rescued_count += 1
                    msg_id = get_message_id(fpath)
                    if msg_id and msg_id in valid_fps:
                        correct_rescues += 1
                    else:
                        spam_rescues += 1

# 4. Analyze current Junk folder
junk_count = 0
junk_path = os.path.join(maildir, ".Junk")
if os.path.exists(junk_path):
    for subdir in ["cur", "new"]:
        dpath = os.path.join(junk_path, subdir)
        if os.path.exists(dpath):
            junk_count += len([f for f in os.listdir(dpath) if os.path.isfile(os.path.join(dpath, f))])

# 5. Analyze Inbox (to ensure no dumping)
inbox_count = 0
for subdir in ["cur", "new"]:
    dpath = os.path.join(maildir, subdir)
    if os.path.exists(dpath):
        inbox_count += len([f for f in os.listdir(dpath) if os.path.isfile(os.path.join(dpath, f))])

# 6. Analyze Drafts and Sent for the report
drafts_sent = []
for folder in [".Drafts", ".Sent"]:
    path = os.path.join(maildir, folder)
    if os.path.exists(path):
        for subdir in ["cur", "new"]:
            dpath = os.path.join(path, subdir)
            if os.path.exists(dpath):
                for fname in os.listdir(dpath):
                    fpath = os.path.join(dpath, fname)
                    if os.path.isfile(fpath):
                        data = parse_email_simple(fpath)
                        drafts_sent.append(data)

# 7. Construct Result JSON
result = {
    "false_positives_folder_exists": (target_folder_path is not None),
    "false_positives_folder_name": target_folder_name,
    "rescued_total": rescued_count,
    "correct_rescues": correct_rescues,
    "spam_rescues": spam_rescues,
    "junk_count": junk_count,
    "inbox_count": inbox_count,
    "emails_composed": drafts_sent
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Set permissions so agent can't modify but we can read
chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="