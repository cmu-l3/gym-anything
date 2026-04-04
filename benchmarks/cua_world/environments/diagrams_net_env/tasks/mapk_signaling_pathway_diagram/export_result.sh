#!/bin/bash
set -e

echo "=== Exporting MAPK Pathway Task Results ==="

# 1. Capture Final Screenshot (Evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
DIAGRAM_FILE="/home/ga/Diagrams/mapk_pathway.drawio"
EXPORT_FILE="/home/ga/Diagrams/exports/mapk_pathway.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Analyze File Status
FILE_EXISTS=false
FILE_MODIFIED=false
EXPORT_EXISTS=false
EXPORT_SIZE=0

if [ -f "$DIAGRAM_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$DIAGRAM_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED=true
    fi
fi

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS=true
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE")
fi

# 4. Parse Draw.io XML Content (using Python)
# We need to extract labels and shape counts to verify content.
# Draw.io files can be plain XML or Compressed XML. This script handles both.

python3 -c "
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import json
import re

def decode_drawio(content):
    # Try parsing as plain XML first
    try:
        tree = ET.fromstring(content)
        if tree.tag == 'mxfile':
            return tree
    except:
        pass
    
    # Try decoding compressed content inside <diagram> tags
    try:
        tree = ET.fromstring(content)
        for diagram in tree.findall('diagram'):
            if diagram.text:
                try:
                    # draw.io compression: Base64 -> Inflate (no header) -> URL Decode sometimes involved
                    data = base64.b64decode(diagram.text)
                    xml_content = zlib.decompress(data, -15).decode('utf-8')
                    return ET.fromstring(urllib.parse.unquote(xml_content))
                except:
                    pass
    except Exception as e:
        pass
    return None

try:
    with open('$DIAGRAM_FILE', 'r') as f:
        raw_content = f.read()

    # If it's a simple XML file, just parse it. If compressed, decode.
    # The setup script created a plain XML, but saving might compress it.
    root = None
    try:
        root = ET.fromstring(raw_content)
        # Check if it has compressed diagrams
        diagrams = root.findall('diagram')
        if diagrams and diagrams[0].text:
             # It's likely compressed, let's try to decode the first page
             decoded_xml = decode_drawio(raw_content)
             if decoded_xml:
                 root = decoded_xml
    except:
        pass

    # Analysis Data
    found_molecules = []
    required_molecules = ['EGF', 'EGFR', 'GRB2', 'SOS', 'RAS', 'RAF', 'MEK', 'ERK', 'ELK1', 'MYC']
    shape_count = 0
    edge_count = 0
    phosphorylation_label = False
    legend_detected = False
    
    if root:
        # Flatten text content for searching
        text_content = ''
        
        for elem in root.iter():
            # Check for mxCell (shapes and edges)
            if 'mxCell' in elem.tag:
                value = elem.get('value', '')
                style = elem.get('style', '')
                vertex = elem.get('vertex')
                edge = elem.get('edge')
                
                # Normalize value (remove HTML tags if any)
                clean_value = re.sub('<[^<]+?>', '', value).upper()
                
                if vertex == '1':
                    shape_count += 1
                    # Check for molecules
                    for mol in required_molecules:
                        if mol in clean_value:
                            found_molecules.append(mol)
                    
                    # Check for Legend keywords
                    if 'LEGEND' in clean_value or ('RED' in clean_value and 'TEAL' in clean_value):
                        legend_detected = True
                        
                if edge == '1':
                    edge_count += 1
                    # Check for Phosphorylation 'P' label on edges or near edges
                    if 'P' in clean_value and len(clean_value) < 5:
                        phosphorylation_label = True

    # Deduplicate found molecules
    found_molecules = list(set(found_molecules))

    result = {
        'shape_count': shape_count,
        'edge_count': edge_count,
        'found_molecules': found_molecules,
        'molecule_count': len(found_molecules),
        'phosphorylation_label': phosphorylation_label,
        'legend_detected': legend_detected
    }
    
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/xml_analysis.json

# 5. Create Final Result JSON
cat <<EOF > /tmp/task_result.json
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "xml_analysis": $(cat /tmp/xml_analysis.json)
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json