#!/bin/bash
echo "=== Exporting game_dialogue_logic_flow result ==="

# Define paths
DRAWIO_FILE="/home/ga/Desktop/quest_flow.drawio"
PNG_FILE="/home/ga/Desktop/quest_flow.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
FILE_EXISTS="false"
PNG_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# 3. Analyze Content using Python (XML parsing)
# We need to extract: Node count, Logic nodes (diamonds), Text content
python3 << 'PYEOF' > /tmp/drawio_analysis.json
import sys
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

file_path = "/home/ga/Desktop/quest_flow.drawio"
result = {
    "node_count": 0,
    "edge_count": 0,
    "diamond_count": 0,
    "ellipse_count": 0,
    "text_content": [],
    "error": None
}

def decode_diagram(raw_data):
    # draw.io often compresses data. It can be raw XML, or Base64+Deflate
    if not raw_data: return None
    try:
        # Try pure XML first
        return ET.fromstring(raw_data)
    except:
        pass
    
    try:
        # Try Base64 -> Inflate (standard draw.io compression)
        decoded = base64.b64decode(raw_data)
        # -15 for raw deflate (no header)
        inflated = zlib.decompress(decoded, -15)
        # URL decode
        xml_str = unquote(inflated.decode('utf-8'))
        return ET.fromstring(xml_str)
    except Exception as e:
        return None

if os.path.exists(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # mxfile -> diagram -> mxGraphModel -> root -> mxCell
        # Data might be compressed inside <diagram> text
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            graph_xml = decode_diagram(diagram_node.text)
            if graph_xml is not None:
                root = graph_xml
        
        # Scan cells
        for cell in root.iter('mxCell'):
            style = cell.get('style', '').lower()
            value = cell.get('value', '').lower()
            
            # Nodes (vertex=1)
            if cell.get('vertex') == '1':
                result['node_count'] += 1
                if value:
                    # Strip HTML tags from labels
                    clean_text = re.sub('<[^<]+?>', '', value)
                    result['text_content'].append(clean_text)
                
                # Check shapes
                if 'rhombus' in style:
                    result['diamond_count'] += 1
                elif 'ellipse' in style or 'shape=ellipse' in style:
                    result['ellipse_count'] += 1
            
            # Edges (edge=1)
            elif cell.get('edge') == '1':
                result['edge_count'] += 1
                if value:
                     clean_text = re.sub('<[^<]+?>', '', value)
                     result['text_content'].append(clean_text)

    except Exception as e:
        result['error'] = str(e)
else:
    result['error'] = "File not found"

print(json.dumps(result))
PYEOF

# 4. Merge results
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/drawio_analysis.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Cleanup permission
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="