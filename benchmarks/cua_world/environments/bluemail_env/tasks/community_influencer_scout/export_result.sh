#!/bin/bash
echo "=== Exporting community_influencer_scout result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Analyze Maildir and CSV using Python
# ============================================================
python3 << 'PYEOF'
import os
import json
import re
import csv

MAILDIR = "/home/ga/Maildir"
CSV_PATH = "/home/ga/Documents/ilug_candidates.csv"
SCOUT_FOLDER = os.path.join(MAILDIR, ".Scout-ILUG")

result = {
    "scout_folder_exists": False,
    "emails_in_folder": 0,
    "flagging_stats": {
        "total_flagged": 0,
        "correctly_flagged": 0,  # Original thread flagged
        "incorrectly_flagged": 0, # Reply flagged
        "missed_flags": 0,       # Original thread NOT flagged
        "correctly_ignored": 0   # Reply NOT flagged
    },
    "csv_exists": False,
    "csv_entries": [],
    "draft_exists": False,
    "draft_details": {}
}

# 1. Analyze Scout-ILUG folder
if os.path.isdir(SCOUT_FOLDER):
    result["scout_folder_exists"] = True
    
    # Scan emails in cur and new
    emails = []
    for subdir in ["cur", "new"]:
        path = os.path.join(SCOUT_FOLDER, subdir)
        if os.path.exists(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                if os.path.isfile(fpath):
                    emails.append(fname)
                    
                    # Parse email for Subject and From
                    try:
                        with open(fpath, 'r', errors='ignore') as f:
                            content = f.read(4096) # Read first 4KB usually enough for headers
                        
                        subject = ""
                        sender = ""
                        
                        # Simple regex parsing for headers (multiline headers not fully handled but sufficient for single line)
                        subj_match = re.search(r'^Subject:\s*(.*)', content, re.MULTILINE | re.IGNORECASE)
                        if subj_match:
                            subject = subj_match.group(1).strip()
                            
                        from_match = re.search(r'^From:\s*(.*)', content, re.MULTILINE | re.IGNORECASE)
                        if from_match:
                            sender = from_match.group(1).strip()
                            
                        # Determine if Flagged
                        # Filename ends with :2,FLAGS. 'F' means Flagged/Starred.
                        is_flagged = 'F' in fname.split(':2,')[-1] if ':2,' in fname else False
                        
                        # Determine if Original Thread (Subject does NOT start with Re:)
                        is_reply = subject.lower().startswith("re:")
                        is_original = not is_reply
                        
                        # Update stats
                        if is_flagged:
                            result["flagging_stats"]["total_flagged"] += 1
                            if is_original:
                                result["flagging_stats"]["correctly_flagged"] += 1
                            else:
                                result["flagging_stats"]["incorrectly_flagged"] += 1
                        else:
                            if is_original:
                                result["flagging_stats"]["missed_flags"] += 1
                            else:
                                result["flagging_stats"]["correctly_ignored"] += 1
                                
                    except Exception as e:
                        print(f"Error parsing {fname}: {e}")

    result["emails_in_folder"] = len(emails)

# 2. Analyze CSV
if os.path.exists(CSV_PATH):
    result["csv_exists"] = True
    try:
        with open(CSV_PATH, 'r', errors='ignore') as f:
            # Read lines, handle potential header
            lines = [l.strip() for l in f.readlines() if l.strip()]
            result["csv_entries"] = lines
    except Exception as e:
        print(f"Error reading CSV: {e}")

# 3. Analyze Drafts
DRAFTS_DIR = os.path.join(MAILDIR, ".Drafts")
for subdir in ["cur", "new"]:
    path = os.path.join(DRAFTS_DIR, subdir)
    if os.path.exists(path):
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            try:
                with open(fpath, 'r', errors='ignore') as f:
                    content = f.read()
                    if "devrel@company.com" in content:
                        result["draft_exists"] = True
                        result["draft_details"] = {"found_in": fname}
                        break
            except:
                pass

# Output JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
PYEOF

# Move to final location with permission handling
cp /tmp/task_result.json /tmp/final_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="