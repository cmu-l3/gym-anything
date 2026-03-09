#!/bin/bash
echo "=== Exporting Conference Schedule Grid Result ==="
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
OUTPUT_FILE="/home/ga/Documents/Summit_Schedule_2025.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Python Script to Analyze ODT Structure (Orientation, Tables, Merges)
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys
import time

output_file = "/home/ga/Documents/Summit_Schedule_2025.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "is_landscape": False,
    "has_table": False,
    "merged_rows_count": 0,
    "content_check": {
        "keynote": False,
        "lunch": False,
        "track_a_session": False,
        "track_b_session": False
    },
    "created_during_task": False,
    "parse_error": None
}

# Check file existence and timestamps
if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    mtime = os.path.getmtime(output_file)
    
    # Check if created/modified after task start
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            start_time = float(f.read().strip())
        if mtime > start_time:
            result["created_during_task"] = True
    except:
        pass

    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # 1. Check Page Orientation (styles.xml)
            # Look for style:print-orientation="landscape" or style:page-layout-properties containing it
            if 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='replace')
                if 'print-orientation="landscape"' in styles:
                    result["is_landscape"] = True
            
            # 2. Check Content and Tables (content.xml)
            if 'content.xml' in zf.namelist():
                content = zf.read('content.xml').decode('utf-8', errors='replace')
                
                # Check for table existence
                if '<table:table' in content:
                    result["has_table"] = True
                
                # Check for merged cells (colspan)
                # ODF uses table:number-columns-spanned="N"
                # We expect spans of 3 for the tracks (or 4 if spanning time too, but usually 3)
                merged_matches = re.findall(r'table:number-columns-spanned="[2-9]"', content)
                result["merged_rows_count"] = len(merged_matches)
                
                # Check content strings
                plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
                result["content_check"]["keynote"] = "future of interoperability" in plain_text
                result["content_check"]["lunch"] = "networking lunch" in plain_text
                result["content_check"]["track_a_session"] = "ai in radiology" in plain_text
                result["content_check"]["track_b_session"] = "fhir standards" in plain_text

    except Exception as e:
        result["parse_error"] = str(e)

# Write result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 4. Permission handling for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="