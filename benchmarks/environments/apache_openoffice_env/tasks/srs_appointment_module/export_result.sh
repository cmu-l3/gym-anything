#!/bin/bash
set -e
echo "=== Exporting SRS Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path definition
OUTPUT_FILE="/home/ga/Documents/SRS_Appointment_Module_v1.odt"
JSON_RESULT="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script to analyze the ODT file
python3 << PYEOF
import zipfile
import json
import os
import re
import sys
import time

output_path = "$OUTPUT_FILE"
task_start = $TASK_START
result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_during_task": False,
    "has_toc": False,
    "h1_count": 0,
    "h2_count": 0,
    "h3_count": 0,
    "table_count": 0,
    "table_rows_total": 0,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "content_check": {
        "req_ids": [],
        "use_cases": [],
        "interfaces": [],
        "keywords": []
    }
}

if os.path.exists(output_path):
    result["file_exists"] = True
    stat = os.stat(output_path)
    result["file_size"] = stat.st_size
    
    # Check modification time
    if stat.st_mtime > task_start:
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # Analyze content.xml
            content = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # Count headings
            result["h1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content))
            result["h2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content))
            result["h3_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="3"', content))
            
            # Check TOC
            if '<text:table-of-content' in content:
                result["has_toc"] = True
            
            # Count Tables
            result["table_count"] = len(re.findall(r'<table:table ', content))
            result["table_rows_total"] = len(re.findall(r'<table:table-row>', content))
            
            # Count Paragraphs (body text)
            result["paragraph_count"] = len(re.findall(r'<text:p[^>]*>', content))

            # Check Page Numbers (often in styles.xml or content.xml)
            styles = ""
            if 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='ignore')
            
            if '<text:page-number' in content or '<text:page-number' in styles:
                result["has_page_numbers"] = True
                
            # Content Verification (extract plain text loosely)
            plain_text = re.sub(r'<[^>]+>', ' ', content)
            
            # Check for REQ IDs
            req_matches = re.findall(r'REQ-F-\d{3}', plain_text)
            result["content_check"]["req_ids"] = list(set(req_matches))
            
            # Check for Use Case IDs
            uc_matches = re.findall(r'UC-\d{3}', plain_text)
            result["content_check"]["use_cases"] = list(set(uc_matches))
            
            # Check for Interface IDs
            if_matches = re.findall(r'IF-\d{3}', plain_text)
            result["content_check"]["interfaces"] = list(set(if_matches))
            
            # Check Keywords
            keywords = ["HIPAA", "FHIR", "Appointment", "Pinnacle", "HL7", "JSON", "IEEE"]
            found_kws = []
            for kw in keywords:
                if kw.lower() in plain_text.lower():
                    found_kws.append(kw)
            result["content_check"]["keywords"] = found_kws

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("$JSON_RESULT", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure result file permissions
chmod 666 "$JSON_RESULT" 2>/dev/null || true

echo "=== Export Complete ==="