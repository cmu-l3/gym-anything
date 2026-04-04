#!/bin/bash
# Export script for donor_mailing_labels task

echo "=== Exporting Donor Mailing Labels Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/golden_circle_labels.odt"
INPUT_CSV="/home/ga/Documents/donor_data.csv"
RESULT_JSON="/tmp/task_result.json"

take_screenshot /tmp/task_final.png

# We use python to bundle the source CSV content and the ODT text content into one JSON
# This allows the host verifier to perform the logic (checking precision/recall)
# without relying on complex bash logic or hidden state files.

python3 << 'PYEOF'
import json
import os
import zipfile
import re
import csv
import time

output_file = "/home/ga/Documents/golden_circle_labels.odt"
input_csv = "/home/ga/Documents/donor_data.csv"
task_start_file = "/tmp/task_start_time.txt"

result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "odt_text_content": "",
    "csv_source_data": [],
    "is_valid_odt": False
}

# 1. Read the source CSV (Ground Truth)
if os.path.exists(input_csv):
    try:
        with open(input_csv, 'r') as f:
            reader = csv.DictReader(f)
            result["csv_source_data"] = list(reader)
    except Exception as e:
        result["csv_error"] = str(e)

# 2. Check the Output File
if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    # Check timestamp
    try:
        file_mtime = os.path.getmtime(output_file)
        with open(task_start_file, 'r') as f:
            start_time = float(f.read().strip())
        
        if file_mtime > start_time:
            result["created_during_task"] = True
    except:
        pass

    # 3. Extract Text from ODT
    try:
        with zipfile.ZipFile(output_file, 'r') as z:
            # Check for mimetype or content.xml to confirm it's ODT
            if 'content.xml' in z.namelist():
                result["is_valid_odt"] = True
                with z.open('content.xml') as cf:
                    content_xml = cf.read().decode('utf-8', errors='replace')
                    # Strip XML tags to get raw text
                    # We keep spaces to ensure names don't merge
                    plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
                    # Normalize whitespace
                    plain_text = re.sub(r'\s+', ' ', plain_text).strip()
                    result["odt_text_content"] = plain_text
    except Exception as e:
        result["odt_parse_error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported JSON. File exists: {result['file_exists']}, CSV rows: {len(result['csv_source_data'])}")
PYEOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json