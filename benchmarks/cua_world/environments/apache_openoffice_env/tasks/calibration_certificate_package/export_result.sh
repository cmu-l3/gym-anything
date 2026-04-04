#!/bin/bash
echo "=== Exporting calibration_certificate_package result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/CalCert_Package_SCP_2024_0147.odt"

# Python script to analyze the ODT file and extract metrics to JSON
python3 << 'PYEOF'
import json
import os
import zipfile
import re
import datetime

output_file = "/home/ga/Documents/CalCert_Package_SCP_2024_0147.odt"
task_start_time = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start_time = int(f.read().strip())
except:
    pass

result = {
    "file_exists": False,
    "file_size": 0,
    "file_mtime": 0,
    "task_start_time": task_start_time,
    "created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "paragraph_count": 0,
    "serials_found": [],
    "lab_name_found": False,
    "client_name_found": False,
    "terms_found": [],
    "parse_error": None,
    "timestamp": datetime.datetime.now().isoformat()
}

# Check if file exists
if not os.path.exists(output_file):
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    print("Output file not found")
    exit(0)

# File stats
stat = os.stat(output_file)
result["file_exists"] = True
result["file_size"] = stat.st_size
result["file_mtime"] = stat.st_mtime
result["created_during_task"] = stat.st_mtime > task_start_time

try:
    with zipfile.ZipFile(output_file, 'r') as zf:
        # Parse content.xml for structure
        content = zf.read('content.xml').decode('utf-8', errors='replace')
        
        # Count structural elements
        # Note: OpenOffice uses text:outline-level for headings
        result["heading1_count"] = len(re.findall(r'<text:h\b[^>]*text:outline-level="1"', content))
        result["heading2_count"] = len(re.findall(r'<text:h\b[^>]*text:outline-level="2"', content))
        result["table_count"] = len(re.findall(r'<table:table\b', content))
        result["paragraph_count"] = len(re.findall(r'<text:p\b', content))
        
        # Extract plain text for content verification
        # Remove XML tags
        plain_text = re.sub(r'<[^>]+>', ' ', content)
        # Normalize whitespace
        plain_text = re.sub(r'\s+', ' ', plain_text).strip().lower()
        
        # Check for serial numbers
        serials = ["27340089", "tc-88712", "pg-445601", "b912004567"]
        found_serials = []
        for sn in serials:
            if sn.lower() in plain_text:
                found_serials.append(sn)
        result["serials_found"] = found_serials
        
        # Check for names
        result["lab_name_found"] = "truepoint" in plain_text
        result["client_name_found"] = "southeastern chemical" in plain_text
        
        # Check for terms
        terms = ["traceability", "uncertainty", "tolerance", "as-found", "as-left", "nist", "a2la"]
        found_terms = []
        for term in terms:
            if term in plain_text:
                found_terms.append(term)
        result["terms_found"] = found_terms

except Exception as e:
    result["parse_error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export analysis complete")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="