#!/bin/bash
# Do NOT use set -e

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DRAWIO_FILE="/home/ga/Desktop/network_topology.drawio"
PNG_FILE="/home/ga/Desktop/network_topology.png"

# Check file existence and modification
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check PNG existence
PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# Deep analysis of the draw.io file (XML parsing)
# We use Python because draw.io files are XML, often compressed
python3 << 'PYEOF' > /tmp/topology_analysis.json 2>/dev/null || true
import json
import re
import os
import base64
import zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/network_topology.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "num_pages": 0,
    "device_matches": 0,
    "ip_pattern_count": 0,
    "zone_boundaries": 0,
    "has_network_terms": False,
    "error": None
}

# Regex patterns for validation
DEVICE_KEYWORDS = [
    r"fw-01", r"core-sw", r"dist-sw", r"web-01", r"dns-ext", 
    r"dc-01", r"fs-01", r"bk-01", r"prn-01", r"dns-int", 
    r"ap-fl", r"eng-ws", r"sales-ws", r"isp-gw"
]
IP_PATTERN = r"10\.0\.(5|10|20|30|99)\.\d+"
ZONE_PATTERN = r"(dmz|server|office|wireless|internet)"

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        # Try standard draw.io compression (base64 -> deflate)
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        # Try URL decoding
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()

        # Count pages
        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages)

        # Collect all cells from all pages
        all_cells = []
        for page in pages:
            # Check for inline content
            inline = list(page.iter('mxCell'))
            if inline:
                all_cells.extend(inline)
            else:
                # Check for compressed content
                inner = decompress_diagram(page.text or '')
                if inner is not None:
                    all_cells.extend(list(inner.iter('mxCell')))
        
        # Fallback: check root level if no diagrams found or uncompressed file
        if not all_cells:
             all_cells = list(root.iter('mxCell'))

        all_text = ""
        
        for cell in all_cells:
            val = (cell.get('value') or '').lower()
            style = (cell.get('style') or '').lower()
            
            # Count shapes (vertices that aren't the root canvas/background)
            if cell.get('vertex') == '1' and cell.get('id') not in ['0', '1']:
                result["num_shapes"] += 1
                all_text += val + " "
                
                # Check for zone boundaries (dashed style)
                if 'dashed=1' in style or 'dashpattern' in style:
                    # Usually zones are container-like
                    if 'container' in style or 'swimlane' in style or 'group' in style or 'rect' in style:
                        result["zone_boundaries"] += 1

            # Count edges
            if cell.get('edge') == '1':
                result["num_edges"] += 1
                all_text += val + " "

        # Analyze collected text
        import re
        
        # Count device matches
        matches = set()
        for kw in DEVICE_KEYWORDS:
            if re.search(kw, all_text, re.IGNORECASE):
                matches.add(kw)
        result["device_matches"] = len(matches)
        
        # Count IPs
        result["ip_pattern_count"] = len(re.findall(IP_PATTERN, all_text))
        
        # Check for general network terms
        if re.search(r"(firewall|switch|router|subnet|vlan)", all_text, re.IGNORECASE):
            result["has_network_terms"] = True

    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "topology_analysis": $(cat /tmp/topology_analysis.json)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="