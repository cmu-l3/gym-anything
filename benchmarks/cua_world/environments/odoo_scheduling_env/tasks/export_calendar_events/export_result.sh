#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting export_calendar_events result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_PATH="/home/ga/Documents/calendar_export.csv"

# 1. Locate the file
# Check strict path first, then fallbacks
ACTUAL_PATH=""
LOCATION_SCORE_MODIFIER="none"

if [ -f "$EXPECTED_PATH" ]; then
    ACTUAL_PATH="$EXPECTED_PATH"
    LOCATION_SCORE_MODIFIER="correct"
else
    # Check Downloads folders
    FOUND=$(find /home/ga/Downloads /home/ga/snap/firefox/common/Downloads -maxdepth 1 -name "*.csv" -newermt "@$TASK_START" 2>/dev/null | head -n 1)
    if [ -n "$FOUND" ]; then
        ACTUAL_PATH="$FOUND"
        LOCATION_SCORE_MODIFIER="fallback"
    fi
fi

# 2. Analyze the file (Python)
# We do the heavy lifting inside the container where we have access to the file and the DB
python3 << PYEOF
import csv
import json
import os
import sys

result = {
    "file_found": False,
    "file_path": "$ACTUAL_PATH",
    "location_status": "$LOCATION_SCORE_MODIFIER",
    "is_valid_csv": False,
    "row_count": 0,
    "headers": [],
    "has_subject": False,
    "has_start": False,
    "has_stop": False,
    "db_match_count": 0,
    "file_created_after_start": False
}

file_path = "$ACTUAL_PATH"
task_start = $TASK_START

if file_path and os.path.exists(file_path):
    result["file_found"] = True
    
    # Check timestamp
    mtime = os.path.getmtime(file_path)
    if mtime > task_start:
        result["file_created_after_start"] = True

    try:
        with open(file_path, 'r', encoding='utf-8-sig', errors='replace') as f:
            # Read header
            reader = csv.reader(f)
            headers = next(reader, None)
            
            if headers:
                result["is_valid_csv"] = True
                result["headers"] = headers
                headers_lower = [h.lower() for h in headers]
                
                # Check required columns
                # Subject/Name
                if any(x in headers_lower for x in ['subject', 'name', 'summary', 'event']):
                    result["has_subject"] = True
                
                # Start Date
                if any(x in headers_lower for x in ['start', 'begin']):
                    result["has_start"] = True
                    
                # End Date
                if any(x in headers_lower for x in ['stop', 'end', 'finish']):
                    result["has_stop"] = True

                # Count rows and check content
                rows = list(reader)
                result["row_count"] = len(rows)
                
                # Load ground truth
                ground_truth = []
                if os.path.exists('/tmp/ground_truth_events.json'):
                    with open('/tmp/ground_truth_events.json', 'r') as gf:
                        ground_truth = json.load(gf)
                
                # Check for matches
                # We try to find the subject column index
                subj_idx = -1
                for i, h in enumerate(headers_lower):
                    if h in ['subject', 'name', 'summary', 'event']:
                        subj_idx = i
                        break
                
                if subj_idx != -1 and ground_truth:
                    matches = 0
                    file_names = set(row[subj_idx] for row in rows if len(row) > subj_idx)
                    for gt_name in ground_truth:
                        if gt_name in file_names:
                            matches += 1
                    result["db_match_count"] = matches

    except Exception as e:
        print(f"Error parsing CSV: {e}", file=sys.stderr)

# Save result
with open('/tmp/analysis_result.json', 'w') as f:
    json.dump(result, f)

print("Analysis complete.")
PYEOF

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare result for export
# We copy the analysis JSON to the standard export location
# Using cp/chmod dance to ensure permissions
cp /tmp/analysis_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="