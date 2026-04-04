#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Basic Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DIAGRAM_PATH="/home/ga/Diagrams/building_4_sld.drawio"
PDF_PATH="/home/ga/Diagrams/exports/building_4_sld_updated.pdf"

# 2. Check PDF Export
PDF_EXISTS="false"
PDF_SIZE="0"
if [ -f "$PDF_PATH" ]; then
    PDF_MTIME=$(stat -c %Y "$PDF_PATH")
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_EXISTS="true"
        PDF_SIZE=$(stat -c %s "$PDF_PATH")
    fi
fi

# 3. Analyze Diagram Content using embedded Python
# This handles both uncompressed XML and compressed/deflated draw.io formats
python3 -c "
import sys
import os
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import json
import re

file_path = '$DIAGRAM_PATH'
result = {
    'file_exists': False,
    'modified_after_start': False,
    'text_content': '',
    'cell_count': 0,
    'has_dp_ev': False,
    'has_feeder_spec': False,
    'has_breaker_spec': False,
    'has_panel_spec': False
}

try:
    if os.path.exists(file_path):
        result['file_exists'] = True
        if os.path.getmtime(file_path) > int('$TASK_START'):
            result['modified_after_start'] = True

        tree = ET.parse(file_path)
        root = tree.getroot()
        
        xml_content = ''
        
        # Check if compressed
        diagrams = root.findall('diagram')
        if diagrams:
            for d in diagrams:
                if d.text:
                    try:
                        # Standard draw.io compression: URL decode -> Base64 decode -> Inflate (no header)
                        data = base64.b64decode(d.text)
                        # -15 for raw inflate (no zlib header)
                        xml_content += zlib.decompress(data, -15).decode('utf-8')
                    except Exception:
                        # Might be plain text or different compression
                        xml_content += d.text
        else:
            # Maybe plain XML format
            with open(file_path, 'r') as f:
                xml_content = f.read()

        result['text_content'] = xml_content.lower()
        result['cell_count'] = len(re.findall(r'<mxCell', xml_content))
        
        # Check for specific requirements in XML
        # Note: XML attributes might be encoded, but value=\"...\" usually contains the text label
        
        txt = result['text_content']
        result['has_dp_ev'] = 'dp-ev' in txt
        result['has_breaker_spec'] = '200a' in txt
        
        # Flexible matching for wire spec (3#3/0)
        # Handle encoded chars if necessary, but usually raw text is present
        result['has_feeder_spec'] = '3#3/0' in txt
        
        # Panel ratings
        result['has_panel_spec'] = '225a' in txt or '480/277v' in txt

except Exception as e:
    result['error'] = str(e)

with open('/tmp/analysis_result.json', 'w') as f:
    json.dump(result, f)
"

# 4. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Merge Results into Final JSON
# We merge the Python analysis with shell-gathered info
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_exported": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "diagram_analysis": $(cat /tmp/analysis_result.json)
}
EOF

# Cleanup permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json