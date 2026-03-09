#!/bin/bash
# Export script for Regex Extraction Product IDs task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Regex Extraction Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Variables to hold verification results
CSV_FOUND="false"
CSV_PATH=""
ROW_COUNT=0
HAS_TARGET_DOMAIN="false"
HAS_UPC_DATA="false"
HAS_REVIEW_DATA="false"
SF_RUNNING="false"
WINDOW_INFO=""

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title for context
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Find the best candidate CSV file
# We look for files created after task start
if [ -d "$EXPORT_DIR" ]; then
    # Use python to perform robust CSV analysis
    python3 << PYEOF
import os
import csv
import re
import json
import glob

export_dir = "$EXPORT_DIR"
task_start_epoch = float($TASK_START_EPOCH)
target_domain = "books.toscrape.com"

# Find files modified after task start
candidates = []
for f in glob.glob(os.path.join(export_dir, "*.csv")):
    try:
        mtime = os.path.getmtime(f)
        if mtime > task_start_epoch:
            candidates.append((f, mtime))
    except:
        pass

# Sort by modification time (newest first)
candidates.sort(key=lambda x: x[1], reverse=True)

best_result = {
    "csv_found": False,
    "csv_path": "",
    "row_count": 0,
    "has_target_domain": False,
    "has_upc_data": False,
    "has_review_data": False
}

# Regex for UPC: 16 char hex (e.g. a897fe39b1053632)
upc_pattern = re.compile(r'^[a-f0-9]{16}$')
# Regex for Review Count: simple integer
review_pattern = re.compile(r'^\d+$')

for csv_path, mtime in candidates:
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            # Read header
            reader = csv.reader(f)
            headers = next(reader, None)
            
            if not headers:
                continue

            rows = list(reader)
            row_count = len(rows)
            
            has_domain = False
            has_upc = False
            has_review = False
            
            # Identify columns
            # Screaming Frog often puts the URL in 'Address' or 'URL'
            url_col_idx = -1
            for i, h in enumerate(headers):
                if h.lower() in ['address', 'url']:
                    url_col_idx = i
                    break
            
            # Check content
            upc_matches = 0
            review_matches = 0
            domain_matches = 0
            
            for row in rows:
                # Check domain
                if url_col_idx >= 0 and len(row) > url_col_idx:
                    if target_domain in row[url_col_idx]:
                        domain_matches += 1

                # Scan all columns in the row for extracted data
                # We don't know exact column index of extraction, so we scan the row
                row_upc_found = False
                row_review_found = False
                
                for cell in row:
                    cell = cell.strip()
                    if not cell:
                        continue
                        
                    # Check UPC
                    if upc_pattern.match(cell):
                        row_upc_found = True
                    
                    # Check Review (careful not to match page size/status code etc)
                    # Review counts on this site are small ints (0-100 usually)
                    # To be safer, we might check if header looks like extraction
                    if review_pattern.match(cell):
                         # Weak signal, but combined with header check is better
                         # We'll rely on the aggregate count
                         row_review_found = True

                if row_upc_found:
                    upc_matches += 1
                if row_review_found:
                    review_matches += 1
            
            if domain_matches > 0:
                has_domain = True
            if upc_matches >= 5: # Threshold to verify it's not random
                has_upc = True
            if review_matches >= 5:
                has_review = True

            # If this file looks like a valid export, use it
            if has_domain:
                best_result = {
                    "csv_found": True,
                    "csv_path": csv_path,
                    "row_count": row_count,
                    "has_target_domain": has_domain,
                    "has_upc_data": has_upc,
                    "has_review_data": has_review
                }
                break # Found a valid one
    except Exception as e:
        print(f"Error processing {csv_path}: {e}")

# Output result to JSON
result_data = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_found": best_result["csv_found"],
    "csv_path": best_result["csv_path"],
    "row_count": best_result["row_count"],
    "has_target_domain": best_result["has_target_domain"],
    "has_upc_data": best_result["has_upc_data"],
    "has_review_data": best_result["has_review_data"],
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/regex_extraction_result.json', 'w') as f:
    json.dump(result_data, f, indent=2)

PYEOF

fi

# Move result to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/regex_extraction_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/regex_extraction_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="