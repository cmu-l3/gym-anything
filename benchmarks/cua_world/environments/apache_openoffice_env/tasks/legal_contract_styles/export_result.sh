#!/bin/bash
# Export script for legal_contract_styles task
# Analyzes the final ODT document for heading styles, TOC, and footer

echo "=== Exporting Legal Contract Styles Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/commercial_lease_final.odt"

python3 << 'PYEOF'
import zipfile
import json
import os
import re

output_file = "/home/ga/Documents/commercial_lease_final.odt"

result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "has_footer": False,
    "total_paragraphs": 0,
    "has_h_elements": False,
    "contains_landlord": False,
    "contains_tenant": False,
    "parse_error": None,
    "export_timestamp": ""
}

import datetime
result["export_timestamp"] = datetime.datetime.now().isoformat()

if not os.path.exists(output_file):
    print(json.dumps(result, indent=2))
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    exit(0)

result["file_exists"] = True
result["file_size"] = os.path.getsize(output_file)

try:
    with zipfile.ZipFile(output_file, 'r') as zf:
        names = zf.namelist()

        # Parse content.xml
        content = zf.read('content.xml').decode('utf-8', errors='replace')

        # Count proper heading elements (text:h with outline-level)
        # These only appear when the agent applies the Heading 1/2 styles
        h1_matches = re.findall(r'<text:h\b[^>]*text:outline-level="1"', content)
        h2_matches = re.findall(r'<text:h\b[^>]*text:outline-level="2"', content)
        result["heading1_count"] = len(h1_matches)
        result["heading2_count"] = len(h2_matches)
        result["has_h_elements"] = (len(h1_matches) + len(h2_matches)) > 0

        # Check for Table of Contents element
        result["has_toc"] = 'text:table-of-content' in content

        # Count total paragraph-like elements for document length estimation
        result["total_paragraphs"] = len(re.findall(r'<text:p\b', content)) + \
                                      len(re.findall(r'<text:h\b', content))

        # Check text content for expected party names
        text_content = re.sub(r'<[^>]+>', ' ', content).lower()
        result["contains_landlord"] = 'pacific properties' in text_content
        result["contains_tenant"] = 'meridian analytics' in text_content

        # Parse styles.xml for footer and page numbers
        if 'styles.xml' in names:
            styles = zf.read('styles.xml').decode('utf-8', errors='replace')
            result["has_footer"] = '<style:footer' in styles or '<text:footer' in styles
            result["has_page_numbers"] = ('text:page-number' in styles or
                                          'text:page-number' in content)

except zipfile.BadZipFile as e:
    result["parse_error"] = f"BadZipFile: {str(e)}"
except Exception as e:
    result["parse_error"] = f"Error: {str(e)}"

print(json.dumps(result, indent=2))
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

if [ $? -ne 0 ]; then
    echo "Python export failed, writing minimal result"
    cat > /tmp/task_result.json << EOF
{"file_exists": false, "parse_error": "Python export failed",
 "heading1_count": 0, "heading2_count": 0,
 "has_toc": false, "has_page_numbers": false, "has_footer": false}
EOF
fi

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="
