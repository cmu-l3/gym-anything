#!/bin/bash
echo "=== Exporting Archive Finding Aid Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze the result file using Python inside the container
# This robustly parses the ODT XML to verify structure without needing complex dependencies
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/Sterling_Finding_Aid.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "series_found": [],
    "content_check": {
        "title_page": False,
        "abstract": False,
        "admin_records": False,
        "financial_records": False
    },
    "export_timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Read content.xml
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Headings (styles)
            # Look for outline-level="1" (Heading 1) and "2" (Heading 2)
            h1_matches = re.findall(r'<text:h\b[^>]*text:outline-level="1"', content)
            h2_matches = re.findall(r'<text:h\b[^>]*text:outline-level="2"', content)
            result["heading1_count"] = len(h1_matches)
            result["heading2_count"] = len(h2_matches)
            
            # Count Tables
            table_matches = re.findall(r'<table:table\b', content)
            result["table_count"] = len(table_matches)
            
            # Check for Table of Contents
            result["has_toc"] = 'text:table-of-content' in content
            
            # Check for Page Numbers (usually in footer styles or content)
            # Also check styles.xml
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
            
            result["has_page_numbers"] = ('text:page-number' in content) or ('text:page-number' in styles_xml)
            
            # Content Text Analysis
            # Remove XML tags for text search
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
            
            # Verify specific content from JSON input
            result["content_check"]["title_page"] = "sterling radiator company" in plain_text
            result["content_check"]["abstract"] = "residential and commercial heating equipment" in plain_text
            
            # Verify Series Headers are present in text (even if style check failed, we check text)
            series_to_check = [
                "series i: administrative", 
                "series ii: financial", 
                "series iii: marketing", 
                "series iv: technical"
            ]
            for s in series_to_check:
                if s in plain_text:
                    result["series_found"].append(s)
            
            result["content_check"]["admin_records"] = "series i: administrative" in plain_text
            result["content_check"]["financial_records"] = "series ii: financial" in plain_text
            
    except Exception as e:
        result["error"] = str(e)

# Write result to temp file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 3. Securely move result for verifier
rm -f /tmp/verifier_result.json 2>/dev/null || true
cp /tmp/task_result.json /tmp/verifier_result.json
chmod 666 /tmp/verifier_result.json 2>/dev/null || true

echo "=== Export Complete ==="