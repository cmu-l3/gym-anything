#!/bin/bash
# Export script for agronomy_scouting_report task

echo "=== Exporting Agronomy Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file metadata
OUTPUT_FILE="/home/ga/Documents/ValleyView_Alfalfa_Report_June2025.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_SIZE=0
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze ODT content using Python
# This script inspects the ODT XML structure for required elements and formatting
python3 << 'PYEOF'
import zipfile
import re
import json
import os
import sys

output_path = "/home/ga/Documents/ValleyView_Alfalfa_Report_June2025.odt"
result = {
    "has_header": False,
    "has_footer": False,
    "heading1_count": 0,
    "has_table": False,
    "content_check": {
        "client_name": False,
        "pest_name": False,
        "chemical_name": False,
        "rei_text": False
    },
    "rei_bold_check": False
}

if not os.path.exists(output_path):
    print(json.dumps(result))
    sys.exit(0)

try:
    with zipfile.ZipFile(output_path, 'r') as zf:
        # Read content.xml (main body)
        content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
        # Read styles.xml (headers/footers often defined here)
        styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')

        # 1. Header/Footer Check
        # Headers/Footers are usually in styles.xml under <style:master-page>
        # or referenced in content.xml
        result['has_header'] = 'AgriScan' in styles_xml or 'AgriScan' in content_xml
        result['has_footer'] = 'text:page-number' in styles_xml or 'text:page-number' in content_xml

        # 2. Headings Check
        # Look for <text:h text:outline-level="1">
        headings = re.findall(r'<text:h[^>]*text:outline-level="1"[^>]*>', content_xml)
        result['heading1_count'] = len(headings)

        # 3. Table Check
        result['has_table'] = '<table:table' in content_xml

        # 4. Content Text Check
        content_plain = re.sub(r'<[^>]+>', ' ', content_xml) # rudimentary text extraction
        result['content_check']['client_name'] = 'Valley View' in content_plain
        result['content_check']['pest_name'] = 'Potato Leafhopper' in content_plain
        result['content_check']['chemical_name'] = 'Warrior' in content_plain
        result['content_check']['rei_text'] = '24 hours' in content_plain

        # 5. Bold REI Check (Advanced)
        # We need to find the style name applied to "24 hours" and check if that style is bold.
        # This is tricky with regex, but we can try a heuristic.
        # Find the text "24 hours" and look at surrounding tags.
        # Pattern: <text:span text:style-name="X">24 hours</text:span>
        # Then look up style "X" for fo:font-weight="bold"
        
        # Regex to find style name of "24 hours"
        span_match = re.search(r'<text:span\s+[^>]*text:style-name="([^"]+)"[^>]*>\s*24 hours\s*</text:span>', content_xml)
        if span_match:
            style_name = span_match.group(1)
            # Look for this style definition in content.xml (automatic styles)
            # Style def: <style:style style:name="style_name" ...> <style:text-properties fo:font-weight="bold" .../> </style:style>
            # We look for the style definition block
            style_pattern = re.compile(r'<style:style\s+[^>]*style:name="' + re.escape(style_name) + r'"[^>]*>(.*?)</style:style>', re.DOTALL)
            style_def = style_pattern.search(content_xml)
            if style_def:
                props = style_def.group(1)
                if 'fo:font-weight="bold"' in props or 'style:font-weight-asian="bold"' in props:
                    result['rei_bold_check'] = True
        
        # Fallback: Check if "24 hours" is inside a bold paragraph style (less likely for inline, but possible)
        # Or check if "24 hours" is adjacent to bold tags in a simpler way if the span parsing fails
        if not result['rei_bold_check']:
            # Sometimes explicit bold is applied directly (less common in ODT than spans)
            pass

except Exception as e:
    result['error'] = str(e)

with open('/tmp/odt_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF

# 4. Merge results
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "odt_analysis": $(cat /tmp/odt_analysis.json)
}
EOF

# 5. Cleanup and permissions
chmod 666 /tmp/task_result.json
echo "Results saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="