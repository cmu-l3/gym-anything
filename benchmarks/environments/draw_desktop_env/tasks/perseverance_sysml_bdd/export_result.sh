#!/bin/bash
# Do NOT use set -e to ensure analysis runs even if intermediate steps fail

echo "=== Exporting Perseverance SysML Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/perseverance_bdd.drawio"
PNG_FILE="/home/ga/Desktop/perseverance_bdd.png"

# 1. Check File Existence and Timestamps
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

PNG_EXISTS="false"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# 2. Analyze Diagram Content using Python
# This script handles draw.io's compressed XML format and parses the graph
python3 << 'PYEOF' > /tmp/bdd_analysis.json 2>/dev/null || true
import sys
import base64
import zlib
import xml.etree.ElementTree as ET
import urllib.parse
import json
import re

filepath = "/home/ga/Desktop/perseverance_bdd.drawio"

result = {
    "parse_success": False,
    "block_count": 0,
    "composition_edges": 0,
    "multiplicity_labels": 0,
    "text_content": [],
    "found_terms": {
        "perseverance": False,
        "mmrtg": False,
        "mobility": False,
        "science": False,
        "sherloc": False,
        "wheels": False
    },
    "mass_property_found": False
}

def decode_diagram(raw_data):
    try:
        # 1. Try URL decoding (plain XML often just url encoded)
        decoded = urllib.parse.unquote(raw_data)
        if decoded.strip().startswith('<'):
            return decoded
        
        # 2. Try Base64 + Inflate (standard draw.io compression)
        # draw.io often sends base64 data that has no header
        try:
            data = base64.b64decode(raw_data)
            return zlib.decompress(data, -15).decode('utf-8')
        except:
            pass
            
        return raw_data
    except Exception as e:
        return None

try:
    tree = ET.parse(filepath)
    root = tree.getroot()
    
    # Diagrams can be stored in <diagram> tags (compressed) or directly in <mxGraphModel>
    diagrams = root.findall('diagram')
    
    xml_content = ""
    if diagrams:
        # Take the first page
        xml_content = decode_diagram(diagrams[0].text)
    else:
        # Maybe uncompressed file
        xml_content = ET.tostring(root, encoding='unicode')
        
    if xml_content:
        model = ET.fromstring(xml_content)
        result["parse_success"] = True
        
        all_text = ""
        
        # Iterate over all cells
        for cell in model.iter('mxCell'):
            val = cell.get('value', '').lower()
            style = cell.get('style', '')
            
            # Count Blocks (vertices that are not edges)
            if cell.get('vertex') == '1':
                result["block_count"] += 1
                all_text += " " + val
                
            # Check Edges for Composition
            # Composition in draw.io usually has 'endArrow=diamond' or 'diamondThin' 
            # AND often 'fillColor=#000000' for black diamond (composition) vs white (aggregation)
            if cell.get('edge') == '1':
                if 'diamond' in style:
                    # Check if it's filled (black)
                    if 'fillcolor=#000000' in style.lower() or 'endarrow=diamond' in style:
                        # endArrow=diamond is usually filled black by default in some themes, 
                        # while diamondThin might need fill color. We'll count any diamond for partial credit
                        # but prioritize filled logic if possible.
                        result["composition_edges"] += 1
                
                # Check labels on edges (multiplicity)
                if val and re.search(r'\b6\b', val):
                    result["multiplicity_labels"] += 1
            
        # Analyze collected text
        result["text_content"] = all_text
        for term in result["found_terms"].keys():
            if term in all_text:
                result["found_terms"][term] = True
                
        if "45 kg" in all_text or "45kg" in all_text:
            result["mass_property_found"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/bdd_analysis.json 2>/dev/null || echo "{}"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json