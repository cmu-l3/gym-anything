#!/bin/bash
set -e

echo "=== Exporting OAuth 2.0 Task Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIAGRAM_FILE="/home/ga/Diagrams/oauth2_flow.drawio"
EXPORT_FILE="/home/ga/Diagrams/exports/oauth2_flow.svg"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Python Script to Parse Draw.io XML ---
# This handles both plain XML and compressed (deflate) formats used by draw.io
cat > /tmp/analyze_drawio.py << 'PYEOF'
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import json
import os
import re

file_path = sys.argv[1]
task_start = int(sys.argv[2])

result = {
    "file_exists": False,
    "file_modified": False,
    "page_count": 0,
    "page_names": [],
    "p1_lifelines": 0,
    "p1_messages": 0,
    "p1_has_alt": False,
    "p2_lifelines": 0,
    "p2_messages": 0,
    "terms_found": [],
    "resource_server_found": False,
    "token_store_found": False
}

if not os.path.exists(file_path):
    print(json.dumps(result))
    sys.exit(0)

result["file_exists"] = True
result["file_modified"] = os.path.getmtime(file_path) > task_start

def decode_node(node_text):
    """Decode standard draw.io compression"""
    try:
        # URL Decode -> Base64 Decode -> Deflate Decompress
        decoded = base64.b64decode(node_text)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except Exception:
        return None

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    diagrams = []
    if root.tag == 'mxfile':
        for d in root.findall('diagram'):
            diagrams.append(d)
    else:
        # Fallback for simple single-page uncompressed
        diagrams.append(root)

    result["page_count"] = len(diagrams)

    all_text_content = ""

    for idx, diag in enumerate(diagrams):
        # Handle compression
        xml_content = diag.text
        if xml_content and not xml_content.strip().startswith('<'):
            xml_str = decode_node(xml_content)
            if xml_str:
                page_root = ET.fromstring(xml_str)
            else:
                page_root = None
        else:
            # Maybe uncompressed directly inside
            if diag.find('mxGraphModel'):
                page_root = diag.find('mxGraphModel').find('root')
            else:
                page_root = None

        page_name = diag.get('name', f'Page-{idx+1}')
        result["page_names"].append(page_name)

        if not page_root:
            continue

        # Count Elements
        lifelines = 0
        messages = 0
        has_alt = False
        
        for cell in page_root.iter('mxCell'):
            style = cell.get('style', '')
            val = cell.get('value', '') or ""
            edge = cell.get('edge')
            vertex = cell.get('vertex')
            
            all_text_content += " " + val

            # Check for Lifeline (style contains umlLifeline or just check shape usage)
            if vertex == '1' and 'umlLifeline' in style:
                lifelines += 1
                if "resource server" in val.lower():
                    result["resource_server_found"] = True
                if "token store" in val.lower():
                    result["token_store_found"] = True
            
            # Check for Messages (edge=1)
            if edge == '1':
                # Filter out simple lines if possible, usually messages have arrow styles
                messages += 1

            # Check for Combined Fragment (alt)
            # Usually style='shape=umlFrame;...' and value starts with 'alt' or contains 'alt'
            if vertex == '1' and ('umlFrame' in style or 'swimlane' in style):
                 if 'alt' in val.lower() or 'alt' in style.lower():
                     has_alt = True
        
        if idx == 0:
            result["p1_lifelines"] = lifelines
            result["p1_messages"] = messages
            result["p1_has_alt"] = has_alt
        elif idx == 1:
            result["p2_lifelines"] = lifelines
            result["p2_messages"] = messages

    # Check Terms
    required_terms = ["access_token", "refresh_token", "bearer", "authorization_code", "401", "introspect"]
    lower_content = all_text_content.lower()
    for term in required_terms:
        if term in lower_content:
            result["terms_found"].append(term)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Execute analysis
ANALYSIS_JSON=$(python3 /tmp/analyze_drawio.py "$DIAGRAM_FILE" "$TASK_START")

# Check Export File
EXPORT_EXISTS="false"
EXPORT_SIZE="0"
if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE")
fi

# Combine results
cat > /tmp/task_result.json << EOF
{
    "analysis": $ANALYSIS_JSON,
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "task_start": $TASK_START,
    "timestamp": "$(date +%s)"
}
EOF

# Safe copy for permissions
cp /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "=== Export Complete ==="
cat /tmp/final_result.json