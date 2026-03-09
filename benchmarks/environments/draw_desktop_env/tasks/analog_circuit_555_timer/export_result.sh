#!/bin/bash
echo "=== Exporting analog_circuit_555_timer result ==="

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DRAWIO_FILE="/home/ga/Desktop/555_schematic.drawio"
PNG_FILE="/home/ga/Desktop/555_schematic.png"

# Check existence
[ -f "$DRAWIO_FILE" ] && DRAWIO_EXISTS="true" || DRAWIO_EXISTS="false"
[ -f "$PNG_FILE" ] && PNG_EXISTS="true" || PNG_EXISTS="false"

# Check file stats
DRAWIO_SIZE=0
if [ "$DRAWIO_EXISTS" = "true" ]; then
    DRAWIO_SIZE=$(stat -c %s "$DRAWIO_FILE")
    DRAWIO_MTIME=$(stat -c %Y "$DRAWIO_FILE")
fi

PNG_SIZE=0
if [ "$PNG_EXISTS" = "true" ]; then
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# Run python script to analyze the XML content
# This handles compressed draw.io files and counts electrical components
python3 << 'PYEOF' > /tmp/circuit_analysis.json 2>/dev/null || true
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/555_schematic.drawio"
analysis = {
    "num_resistors": 0,
    "num_capacitors": 0,
    "num_leds": 0,
    "num_ics": 0,
    "num_connections": 0,
    "labels_found": [],
    "uses_electrical_lib": False,
    "error": None
}

def decode_diagram(text):
    if not text: return None
    try:
        # Check if URL encoded
        if '%' in text:
            decoded = unquote(text)
            if decoded.strip().startswith('<'):
                return ET.fromstring(decoded)
        
        # Check if Base64 + Deflate
        data = base64.b64decode(text)
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return ET.fromstring(xml_str)
    except Exception as e:
        return None

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Flatten cells from all pages
        cells = []
        
        # Check for diagrams
        diagrams = root.findall('diagram')
        if diagrams:
            for d in diagrams:
                # Try to get inner mxGraphModel
                if d.text:
                    graph_model = decode_diagram(d.text)
                    if graph_model is not None:
                        cells.extend(graph_model.iter('mxCell'))
                else:
                    # Look for direct children if not compressed
                    cells.extend(d.iter('mxCell'))
        else:
            # Maybe directly mxfile/mxGraphModel
            cells.extend(root.iter('mxCell'))
            
        all_text = ""
        
        for cell in cells:
            style = (cell.get('style') or "").lower()
            val = (cell.get('value') or "").lower()
            
            all_text += " " + val
            
            if cell.get('edge') == '1':
                analysis['num_connections'] += 1
            elif cell.get('vertex') == '1':
                # Detection heuristics based on draw.io electrical library styles
                if 'resistor' in style or 'resistor' in val:
                    analysis['num_resistors'] += 1
                elif 'capacitor' in style or 'capacitor' in val:
                    analysis['num_capacitors'] += 1
                elif 'diode' in style or 'led' in style or 'led' in val:
                    analysis['num_leds'] += 1
                elif 'ic' in style or 'logic' in style or '555' in val:
                    analysis['num_ics'] += 1
                
                # Check for electrical library usage
                if 'mxgraph.electrical' in style:
                    analysis['uses_electrical_lib'] = True
                    
        # Check labels
        expected_labels = ["r1", "r2", "r3", "c1", "d1", "555", "1k", "470k", "1uf", "220"]
        found = []
        for lbl in expected_labels:
            if lbl in all_text:
                found.append(lbl)
        analysis['labels_found'] = found
        
    else:
        analysis['error'] = "File not found"

except Exception as e:
    analysis['error'] = str(e)

print(json.dumps(analysis))
PYEOF

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_size": $DRAWIO_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/circuit_analysis.json || echo "{}")
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="