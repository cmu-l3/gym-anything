#!/bin/bash
echo "=== Exporting weekend_email_audit results ==="

source /workspace/scripts/task_utils.sh

# 1. Snapshot
take_screenshot /tmp/task_final.png

# 2. Python Analysis
# We analyze:
# - The contents of the 'Weekend-Review' folder (Precision/Recall)
# - The Inbox (remaining count)
# - The Report file (content check)
# - The Drafts (email check)

python3 << 'PYEOF'
import os
import json
import email
import email.utils
import re

MAILDIR = "/home/ga/Maildir"
REPORT_PATH = "/home/ga/Documents/weekend_audit_report.txt"
GT_PATH = "/tmp/ground_truth.json"

# Load Ground Truth
try:
    with open(GT_PATH, 'r') as f:
        gt = json.load(f)
    gt_weekend_count = gt.get('weekend_count', 0)
    gt_subjects = set(gt.get('weekend_subjects', []))
except:
    gt_weekend_count = 0
    gt_subjects = set()

# Helper to check if email is weekend
def is_weekend(fpath):
    try:
        with open(fpath, 'r', errors='ignore') as fp:
            msg = email.message_from_file(fp)
            date_str = msg.get('Date')
            subject = msg.get('Subject', '')
            if date_str:
                pt = email.utils.parsedate(date_str)
                if pt:
                    wday = pt[6]
                    if wday == 5 or wday == 6:
                        return True, subject
    except:
        pass
    return False, ""

# helper to parse drafts
def parse_email_content(fpath):
    try:
        with open(fpath, 'r', errors='ignore') as f:
            msg = email.message_from_file(f)
            return {
                "to": msg.get("To", ""),
                "subject": msg.get("Subject", ""),
                "body": msg.get_payload() if not msg.is_multipart() else msg.get_payload(0).get_payload()
            }
    except:
        return {}

# 1. Analyze Weekend-Review Folder
# Name might be .Weekend-Review or .Weekend-Review (hidden in Maildir)
# BlueMail creates folders at root of Maildir usually prefixed with .
target_folder = None
for d in os.listdir(MAILDIR):
    if d.lower() == ".weekend-review":
        target_folder = os.path.join(MAILDIR, d)
        break

true_positives = 0
false_positives = 0
found_subjects = []

if target_folder and os.path.isdir(target_folder):
    for subdir in ["cur", "new"]:
        p = os.path.join(target_folder, subdir)
        if os.path.isdir(p):
            for f in os.listdir(p):
                fpath = os.path.join(p, f)
                if os.path.isfile(fpath):
                    is_wk, subj = is_weekend(fpath)
                    if is_wk:
                        true_positives += 1
                        found_subjects.append(subj)
                    else:
                        false_positives += 1

# 2. Analyze Report
report_exists = os.path.exists(REPORT_PATH)
report_content = ""
report_stats = {"has_count": False, "has_subjects": False}

if report_exists:
    with open(REPORT_PATH, 'r', errors='ignore') as f:
        report_content = f.read()
    
    # Check for numbers
    if re.search(r'\d+', report_content):
        report_stats["has_count"] = True
    
    # Check for subjects (simple overlap check)
    match_count = 0
    for subj in gt_subjects:
        if subj in report_content:
            match_count += 1
    if match_count >= 2: # At least 2 subjects listed
        report_stats["has_subjects"] = True

# 3. Analyze Drafts
draft_found = False
draft_details = {}
drafts_dir = os.path.join(MAILDIR, ".Drafts")
if os.path.isdir(drafts_dir):
    for subdir in ["cur", "new"]:
        p = os.path.join(drafts_dir, subdir)
        if os.path.isdir(p):
            for f in os.listdir(p):
                fpath = os.path.join(p, f)
                if os.path.isfile(fpath):
                    data = parse_email_content(fpath)
                    if "hr-director@company.com" in data.get("to", "").lower():
                        draft_found = True
                        draft_details = data
                        break
        if draft_found: break

# Also check Sent folder
if not draft_found:
    sent_dir = os.path.join(MAILDIR, ".Sent")
    if os.path.isdir(sent_dir):
        for subdir in ["cur", "new"]:
            p = os.path.join(sent_dir, subdir)
            if os.path.isdir(p):
                for f in os.listdir(p):
                    fpath = os.path.join(p, f)
                    if os.path.isfile(fpath):
                        data = parse_email_content(fpath)
                        if "hr-director@company.com" in data.get("to", "").lower():
                            draft_found = True
                            draft_details = data
                            break
            if draft_found: break

# Calculate stats
moved_total = true_positives + false_positives
precision = 0.0
if moved_total > 0:
    precision = true_positives / moved_total

recall = 0.0
if gt_weekend_count > 0:
    recall = true_positives / gt_weekend_count

result = {
    "folder_created": bool(target_folder),
    "folder_name": os.path.basename(target_folder) if target_folder else None,
    "true_positives": true_positives,
    "false_positives": false_positives,
    "gt_weekend_count": gt_weekend_count,
    "precision": precision,
    "recall": recall,
    "report_exists": report_exists,
    "report_stats": report_stats,
    "draft_found": draft_found,
    "draft_details": draft_details,
    "timestamp": time.time()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="