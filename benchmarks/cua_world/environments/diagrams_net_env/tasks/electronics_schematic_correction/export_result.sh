#!/bin/bash
echo "=== Exporting Electronics Schematic Correction Results ==="

# Define paths
DRAFT_FILE="/home/ga/Diagrams/555_timer_draft.drawio"
EXPORT_PDF="/home/ga/Diagrams/exports/555_timer_final.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Timestamps and Existence
FILE_EXISTS=false
FILE_MODIFIED=false
EXPORT_EXISTS=false

if [ -f "$DRAFT_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$DRAFT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED=true
    fi
fi

if [ -f "$EXPORT_PDF" ]; then
    EXPORT_EXISTS=true
fi

# 3. Analyze Diagram Content using Python
# We need to decode the compressed XML in the .drawio file to check for components
python3 -c "
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import json
import re

def decode_drawio(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        diagram = root.find('diagram')
        if diagram is None:
            return ''
        
        # If text is directly XML (uncompressed)
        if diagram.text and '<mxGraphModel>' in diagram.text:
            return diagram.text

        # Decode compressed content
        if diagram.text:
            compressed = base64.b64decode(diagram.text)
            xml_str = zlib.decompress(compressed, -15).decode('utf-8')
            return urllib.parse.unquote(xml_str)
        return ''
    except Exception as e:
        return ''

xml_content = decode_drawio('$DRAFT_FILE')

# Analysis Results
data = {
    'has_1k': False,
    'has_10k': False,
    'has_10uF': False,
    'has_10nF': False,
    'has_470': False,
    'has_LED': False,
    'has_Pin4_VCC': False,
    'total_edges': 0
}

if xml_content:
    # Check for text labels (Values)
    # Using simple string search on the decoded XML is robust enough for label checking
    # Normalizing content to lower case for search, but keeping case for specific checks if needed
    lower_content = xml_content.lower()
    
    # 1. Resistor Values (Corrected)
    # Looking for 'value=\"1k\"' or label containing 1k
    # Simple substring search usually works because draw.io stores labels in 'value' attributes
    if '1k' in xml_content or '1k' in lower_content:
        data['has_1k'] = True
    if '10k' in xml_content or '10k' in lower_content:
        data['has_10k'] = True
        
    # 2. Capacitors
    if '10uF' in xml_content or '10uf' in lower_content or '10µf' in lower_content:
        data['has_10uF'] = True
    if '10nF' in xml_content or '10nf' in lower_content or '0.01uf' in lower_content:
        data['has_10nF'] = True
        
    # 3. Output Stage
    if '470' in xml_content:
        data['has_470'] = True
    if 'LED' in xml_content or 'led' in lower_content or 'light emitting diode' in lower_content:
        data['has_LED'] = True
    
    # 4. Connectivity Heuristics
    # We count 'edge=\"1\"' elements to see if wires were added
    # Initial draft had ~2 wires. Completed should have many more.
    data['total_edges'] = lower_content.count('edge=\"1\"')
    
    # To check Pin 4 to VCC specifically is hard without graph parsing, 
    # but we can check if there are edges connecting to the IC and VCC
    # or rely on the total edge count increase + VLM.

print(json.dumps(data))
" > /tmp/xml_analysis.json

# 4. Combine Results
cat > /tmp/result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "export_exists": $EXPORT_EXISTS,
    "xml_analysis": $(cat /tmp/xml_analysis.json || echo "{}"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="