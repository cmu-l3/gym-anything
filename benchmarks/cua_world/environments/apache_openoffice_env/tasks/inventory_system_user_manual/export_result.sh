#!/bin/bash
echo "=== Exporting Inventory System User Manual Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Define output path
OUTPUT_FILE="/home/ga/Documents/StockPulse_WMS_User_Manual.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Python script to parse ODT and analyze content
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys
import datetime

output_file = "/home/ga/Documents/StockPulse_WMS_User_Manual.odt"
task_start = int(sys.argv[1]) if len(sys.argv) > 1 else 0

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
    "word_count": 0,
    "keywords_found": [],
    "error_codes_found": 0,
    "parse_error": None
}

if os.path.exists(output_file):
    result["file_exists"] = True
    stats = os.stat(output_file)
    result["file_size"] = stats.st_size
    
    # Check modification time
    if stats.st_mtime > task_start:
        result["file_created_during_task"] = True

    try:
        with zipfile.ZipFile(output_file, 'r') as z:
            # Parse content.xml
            content_xml = z.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Headings (Structure)
            result["heading1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content_xml))
            result["heading2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content_xml))
            
            # Count Tables
            result["table_count"] = len(re.findall(r'<table:table\b', content_xml))
            
            # Check TOC
            result["has_toc"] = 'text:table-of-content' in content_xml
            
            # Count Paragraphs
            # Includes headings and standard paragraphs
            result["paragraph_count"] = len(re.findall(r'<text:p\b', content_xml)) + \
                                       len(re.findall(r'<text:h\b', content_xml))
            
            # Extract Text for content analysis
            # Simple regex to strip tags
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
            result["word_count"] = len(plain_text.split())
            
            # Content Keyword Checks
            keywords = ["StockPulse", "Cascade Distribution", "Receiving", "Picking", "Cycle Count", "WMS"]
            found = []
            for k in keywords:
                if k.lower() in plain_text.lower():
                    found.append(k)
            result["keywords_found"] = found
            
            # Check for Error Codes (Pattern ERR-XXXX)
            error_matches = re.findall(r'ERR-\d{4}', plain_text)
            result["error_codes_found"] = len(set(error_matches))
            
            # Parse styles.xml for Footer/Page Numbers
            if 'styles.xml' in z.namelist():
                styles_xml = z.read('styles.xml').decode('utf-8', errors='replace')
                # Check for page number field in styles (footer) or content
                has_pn_styles = 'text:page-number' in styles_xml
                has_pn_content = 'text:page-number' in content_xml
                result["has_page_numbers"] = has_pn_styles or has_pn_content

    except Exception as e:
        result["parse_error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF "$TASK_START"

# 4. Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="