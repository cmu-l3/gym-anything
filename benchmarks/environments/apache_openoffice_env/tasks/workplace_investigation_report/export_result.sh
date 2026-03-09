#!/bin/bash
echo "=== Exporting Workplace Investigation Report Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_FILE="/home/ga/Documents/PSS-EEO-2024-017_Investigation_Report.odt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Run Python script to analyze the ODT file
# We use Python here because parsing XML/ODT structures in bash is fragile
python3 << 'PYEOF'
import json
import os
import zipfile
import re
import sys

output_path = "/home/ga/Documents/PSS-EEO-2024-017_Investigation_Report.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "content_check": {
        "case_number_found": False,
        "complainant_found": False,
        "respondent_found": False,
        "findings_found": False
    }
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # Read content.xml
            content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # Read styles.xml (for page numbers/footers)
            try:
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')
            except:
                styles_xml = ""

            # Check for Heading 1 (<text:h ... outline-level="1">)
            # Regex handles potential attributes between text:h and outline-level
            h1_matches = re.findall(r'<text:h[^>]*outline-level="1"', content_xml)
            result["heading1_count"] = len(h1_matches)

            # Check for Heading 2 (<text:h ... outline-level="2">)
            h2_matches = re.findall(r'<text:h[^>]*outline-level="2"', content_xml)
            result["heading2_count"] = len(h2_matches)

            # Check for Tables (<table:table>)
            table_matches = re.findall(r'<table:table\b', content_xml)
            result["table_count"] = len(table_matches)

            # Check for Table of Contents (<text:table-of-content>)
            if 'text:table-of-content' in content_xml:
                result["has_toc"] = True
                
            # Check for Page Numbers (text:page-number in styles or content)
            if 'text:page-number' in content_xml or 'text:page-number' in styles_xml:
                result["has_page_numbers"] = True
            
            # Count paragraphs (<text:p>) - rough proxy for content length
            paras = re.findall(r'<text:p\b', content_xml)
            result["paragraph_count"] = len(paras)

            # Extract text for content verification
            # Remove XML tags
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
            
            if "pss-eeo-2024-017" in plain_text:
                result["content_check"]["case_number_found"] = True
            if "vargas" in plain_text:
                result["content_check"]["complainant_found"] = True
            if "haines" in plain_text:
                result["content_check"]["respondent_found"] = True
            if "substantiated" in plain_text:
                result["content_check"]["findings_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
PYEOF

# Ensure the result file has correct permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="