#!/bin/bash
echo "=== Exporting Task Results ==="

# Source task utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
OUTPUT_FILE="/home/ga/Documents/Maplewood_Salary_Schedule_2024_2025.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze ODT file using embedded Python script
# We use Python to parse the ODT (zip) and extract content/structure
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_path = "/home/ga/Documents/Maplewood_Salary_Schedule_2024_2025.odt"
task_start = int(os.getenv('TASK_START', 0))

result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "content_checks": {
        "val_42500": False,
        "val_72835": False,
        "val_84750": False,
        "val_6200": False,
        "district_name": False
    },
    "text_length": 0
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
            # Read content.xml for body content
            content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # Read styles.xml for header/footer definitions
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')

            # 1. Count Headings (Outline Level 1 and 2)
            # Look for <text:h text:outline-level="1">
            result["heading1_count"] = len(re.findall(r'text:outline-level="1"', content_xml))
            result["heading2_count"] = len(re.findall(r'text:outline-level="2"', content_xml))

            # 2. Count Tables
            # Look for <table:table>
            result["table_count"] = len(re.findall(r'<table:table\b', content_xml))

            # 3. Check for TOC
            # Look for <text:table-of-content>
            result["has_toc"] = '<text:table-of-content' in content_xml

            # 4. Check for Page Numbers
            # Usually <text:page-number> inside styles.xml or content.xml
            result["has_page_numbers"] = ('<text:page-number' in content_xml) or ('<text:page-number' in styles_xml)

            # 5. Count Paragraphs (simple proxy for length)
            result["paragraph_count"] = len(re.findall(r'<text:p\b', content_xml))

            # 6. Extract Plain Text for Content Checks
            # Remove tags
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
            result["text_length"] = len(plain_text)
            
            # Check specific values
            result["content_checks"]["val_42500"] = "42,500" in plain_text or "42500" in plain_text
            result["content_checks"]["val_72835"] = "72,835" in plain_text or "72835" in plain_text
            result["content_checks"]["val_84750"] = "84,750" in plain_text or "84750" in plain_text
            result["content_checks"]["val_6200"] = "6,200" in plain_text or "6200" in plain_text
            result["content_checks"]["district_name"] = "Maplewood" in plain_text

    except Exception as e:
        print(f"Error parsing ODT: {e}", file=sys.stderr)
        result["error"] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# 4. Permissions check
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json