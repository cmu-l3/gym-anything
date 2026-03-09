#!/bin/bash
# Export script for bcp_document_create task

echo "=== Exporting BCP Document Create Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/Meridian_BCP_2024.odt"

result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "has_footer": False,
    "has_header": False,
    "table_count": 0,
    "paragraph_count": 0,
    "text_length": 0,
    "mentions_company": False,
    "mentions_bcp_terms": False,
    "mentions_rto": False,
    "parse_error": None,
    "export_timestamp": datetime.datetime.now().isoformat()
}

if not os.path.exists(output_file):
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
    exit(0)

result["file_exists"] = True
result["file_size"] = os.path.getsize(output_file)

try:
    with zipfile.ZipFile(output_file, 'r') as zf:
        names = zf.namelist()
        content = zf.read('content.xml').decode('utf-8', errors='replace')

        # Heading counts (proper styles only)
        result["heading1_count"] = len(
            re.findall(r'<text:h\b[^>]*text:outline-level="1"', content))
        result["heading2_count"] = len(
            re.findall(r'<text:h\b[^>]*text:outline-level="2"', content))

        # TOC
        result["has_toc"] = 'text:table-of-content' in content

        # Tables
        result["table_count"] = len(re.findall(r'<table:table\b', content))

        # Paragraphs and text length
        result["paragraph_count"] = (
            len(re.findall(r'<text:p\b', content)) +
            len(re.findall(r'<text:h\b', content))
        )
        plain_text = re.sub(r'<[^>]+>', ' ', content)
        result["text_length"] = len(plain_text.strip())

        text_lower = plain_text.lower()
        result["mentions_company"] = (
            'meridian' in text_lower or 'mlp' in text_lower)
        bcp_keywords = ['business continuity', 'recovery', 'emergency',
                        'risk assessment', 'incident', 'disaster']
        result["mentions_bcp_terms"] = any(k in text_lower for k in bcp_keywords)
        result["mentions_rto"] = ('rto' in text_lower or
                                   'recovery time' in text_lower or
                                   'recovery objective' in text_lower)

        # Styles.xml for header/footer
        if 'styles.xml' in names:
            styles = zf.read('styles.xml').decode('utf-8', errors='replace')
            result["has_footer"] = '<style:footer' in styles
            result["has_header"] = '<style:header' in styles
            result["has_page_numbers"] = (
                'text:page-number' in styles or
                'text:page-number' in content)

except Exception as e:
    result["parse_error"] = str(e)

print(json.dumps(result, indent=2))
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="
