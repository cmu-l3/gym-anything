#!/bin/bash
# Export script for freight_shipping_docs task

echo "=== Exporting Freight Shipping Docs Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Define output path
OUTPUT_FILE="/home/ga/Documents/GLI_BOL_2024_03847.odt"
RESULT_JSON="/tmp/task_result.json"

# 3. Use Python to parse the ODT file and extract verification metrics
# We execute this inside the container to access the file directly
python3 << 'PYEOF'
import json
import os
import zipfile
import re
import datetime

output_file = "/home/ga/Documents/GLI_BOL_2024_03847.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_footer": False,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "text_content_found": [],
    "export_timestamp": datetime.datetime.now().isoformat()
}

# Key strings to look for in the text
target_strings = {
    "bol_number": "GLI-BOL-2024-03847",
    "carrier": "Great Lakes",
    "nmfc_1": "170700",
    "nmfc_2": "100240",
    "hazmat_un1": "UN1133",
    "hazmat_un2": "UN1956",
    "hazmat_un3": "UN3481",
    "city_1": "Akron",
    "city_2": "Davenport",
    "city_3": "Moorhead"
}

if not os.path.exists(output_file):
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)
    print("Output file not found")
    raise SystemExit(0)

result["file_exists"] = True
result["file_size"] = os.path.getsize(output_file)

try:
    # ODT is a zip file
    with zipfile.ZipFile(output_file, 'r') as z:
        # 1. Analyze content.xml
        with z.open('content.xml') as cf:
            content = cf.read().decode('utf-8', errors='replace')

        # Count Heading 1 (outline level 1)
        h1_matches = re.findall(r'<text:h[^>]+text:outline-level="1"', content)
        result["heading1_count"] = len(h1_matches)

        # Count Heading 2 (outline level 2)
        h2_matches = re.findall(r'<text:h[^>]+text:outline-level="2"', content)
        result["heading2_count"] = len(h2_matches)

        # Count Tables
        table_matches = re.findall(r'<table:table\b', content)
        result["table_count"] = len(table_matches)

        # Check for TOC
        result["has_toc"] = 'text:table-of-content' in content

        # Count paragraphs (rough estimate of content)
        para_matches = re.findall(r'<text:p\b', content)
        result["paragraph_count"] = len(para_matches)

        # Extract plain text for content searching
        plain_text = re.sub(r'<[^>]+>', ' ', content)
        # Normalize whitespace
        plain_text = re.sub(r'\s+', ' ', plain_text)

        # Check for target strings
        found_keys = []
        for key, val in target_strings.items():
            # Case insensitive check
            if val.lower() in plain_text.lower():
                found_keys.append(key)
        result["text_content_found"] = found_keys

        # 2. Analyze styles.xml for footer/page numbers
        try:
            with z.open('styles.xml') as sf:
                styles = sf.read().decode('utf-8', errors='replace')
            result["has_footer"] = '<style:footer' in styles or '<text:footer' in styles
            result["has_page_numbers"] = 'text:page-number' in styles or 'text:page-number' in content
        except Exception:
            # Sometimes styles.xml might be missing or different, but content.xml often has the page-number field too
            pass

except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export analysis complete. File size: {result['file_size']}")
PYEOF

# 4. Set permissions so host can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "=== Export Complete ==="