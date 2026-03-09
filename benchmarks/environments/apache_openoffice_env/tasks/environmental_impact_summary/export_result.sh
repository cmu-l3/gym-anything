#!/bin/bash
echo "=== Exporting Environmental Impact Summary Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/Ridgeline_Wind_EIA_Summary.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to parse the ODT file (which is a zip)
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime
import time

output_path = "/home/ga/Documents/Ridgeline_Wind_EIA_Summary.odt"
task_start = int(os.environ.get('TASK_START', 0))

result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "keywords_found": [],
    "parse_error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    stats = os.stat(output_path)
    result["file_size"] = stats.st_size
    result["created_during_task"] = stats.st_mtime > task_start

    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # Parse content.xml
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Headings (styles)
            # Look for outline-level="1" or "2"
            result["heading1_count"] = len(re.findall(r'text:outline-level="1"', content))
            result["heading2_count"] = len(re.findall(r'text:outline-level="2"', content))
            
            # Count Tables
            result["table_count"] = len(re.findall(r'<table:table\b', content))
            
            # Check for TOC
            result["has_toc"] = 'text:table-of-content' in content
            
            # Count Paragraphs (simple heuristic)
            result["paragraph_count"] = len(re.findall(r'<text:p\b', content))
            
            # Check content keywords
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
            keywords = ["indiana bat", "myotis", "dba", "ridgeline", "garrett"]
            found = []
            for k in keywords:
                if k in plain_text:
                    found.append(k)
            result["keywords_found"] = found
            
            # Check styles.xml for footer page numbers
            if 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='replace')
                # Check for footer style definition or page number field in content/styles
                has_footer_style = '<style:footer' in styles
                has_page_num = 'text:page-number' in styles or 'text:page-number' in content
                result["has_page_numbers"] = has_footer_style and has_page_num

    except Exception as e:
        result["parse_error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Move result to final location with permissive permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="