#!/bin/bash
echo "=== Exporting Digital Logic Task Result ==="

# Files
DRAWIO_FILE="/home/ga/Diagrams/full_adder.drawio"
PNG_FILE="/home/ga/Diagrams/exports/full_adder.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date +%s)

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize JSON fields
FILE_EXISTS="false"
FILE_MODIFIED="false"
PNG_EXISTS="false"
SHAPE_COUNTS="{}"
LABELS_FOUND="[]"
TOPOLOGY_CHECK="false"

# Check if drawio file exists
if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Python script to parse the drawio XML (handles compression)
    # Extracts shape types and labels
    cat > /tmp/parse_drawio.py << 'PYEOF'
import sys
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import json
import re

def decode_diagram(text):
    try:
        # standard draw.io compression
        decoded = base64.b64decode(text)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except:
        return text # might be uncompressed

try:
    tree = ET.parse(sys.argv[1])
    root = tree.getroot()
    
    xml_content = ""
    if root.tag == 'mxfile':
        for diagram in root.findall('diagram'):
            if diagram.text:
                xml_content = decode_diagram(diagram.text)
                break # Just take the first page
    else:
        xml_content = ET.tostring(root, encoding='utf-8')

    # If we decoded inner XML, parse it again
    if xml_content.strip().startswith('<'):
        try:
            root = ET.fromstring(xml_content)
        except:
            pass # Use original root if this fails

    # Analysis
    counts = {"xor": 0, "and": 0, "or": 0, "gate_shapes": 0}
    labels = []
    
    # Build a graph for connectivity: source_id -> [target_ids]
    connections = []
    
    for cell in root.iter('mxCell'):
        style = (cell.get('style') or "").lower()
        value = (cell.get('value') or "").strip()
        
        # Check for shapes
        if 'vertex' in cell.attrib:
            if value:
                labels.append(value)
            
            # Heuristic for logic gates based on draw.io library styles
            # Style examples: "shape=xor", "verticalLabelPosition...shape=mxgraph.electrical.logic_gates.logic_gate;operation=xor;"
            if 'xor' in style:
                counts['xor'] += 1
                counts['gate_shapes'] += 1
            elif 'and' in style and 'operand' not in style: # avoid 'stand-alone' text matches if possible, though 'and' is rare in style keys other than shape
                counts['and'] += 1
                counts['gate_shapes'] += 1
            elif 'or' in style and 'xor' not in style and 'connector' not in style:
                counts['or'] += 1
                counts['gate_shapes'] += 1
                
        # Check edges
        if 'edge' in cell.attrib:
            src = cell.get('source')
            trg = cell.get('target')
            if src and trg:
                connections.append((src, trg))

    result = {
        "counts": counts,
        "labels": labels,
        "connection_count": len(connections)
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "counts": {"xor":0, "and":0, "or":0}, "labels": []}))
PYEOF

    PARSED_DATA=$(python3 /tmp/parse_drawio.py "$DRAWIO_FILE")
else
    PARSED_DATA='{"counts": {"xor":0, "and":0, "or":0}, "labels": [], "connection_count": 0}'
fi

# Check PNG export
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "timestamp": $TIMESTAMP,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "parsed_data": $PARSED_DATA
}
EOF

echo "Result stored in /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="