#!/bin/bash
echo "=== Exporting TCP State Machine Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DIAGRAM_PATH="/home/ga/Diagrams/tcp_state_machine.drawio"
EXPORT_PATH="/home/ga/Diagrams/tcp_state_machine.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Parse the draw.io XML to extract graph structure for verification
# We use Python here to create a JSON representation of the graph
python3 -c "
import sys
import xml.etree.ElementTree as ET
import json
import re
import os
import urllib.parse
import base64
import zlib

def decode_drawio_content(encoded_text):
    try:
        # draw.io often URL-encodes, then Base64, then Deflate
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded + '==') # padding safety
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        return None

def extract_graph(file_path):
    if not os.path.exists(file_path):
        return {'error': 'File not found'}

    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Handle compressed diagrams (mxfile -> diagram -> mxGraphModel)
        diagrams = root.findall('diagram')
        if diagrams:
            # Look for the first diagram
            diagram = diagrams[0]
            if diagram.text and diagram.text.strip():
                # It's compressed
                xml_content = decode_drawio_content(diagram.text)
                if xml_content:
                    root = ET.fromstring(xml_content)
                else:
                    return {'error': 'Failed to decode diagram'}
            else:
                # It might be uncompressed inside <diagram>
                root = diagram

        # Find all cells
        cells = root.findall('.//mxCell')
        
        nodes = []
        edges = []
        
        for cell in cells:
            cid = cell.get('id')
            val = cell.get('value', '')
            style = cell.get('style', '')
            
            # Identify nodes (vertices)
            if cell.get('vertex') == '1':
                # Strip HTML tags from value if present
                clean_val = re.sub('<[^<]+?>', '', val).strip()
                if clean_val:
                    nodes.append({'id': cid, 'label': clean_val, 'style': style})
            
            # Identify edges
            if cell.get('edge') == '1':
                source = cell.get('source')
                target = cell.get('target')
                clean_val = re.sub('<[^<]+?>', '', val).strip()
                edges.append({
                    'id': cid, 
                    'source': source, 
                    'target': target, 
                    'label': clean_val
                })
                
        return {'nodes': nodes, 'edges': edges}
        
    except Exception as e:
        return {'error': str(e)}

graph_data = extract_graph('$DIAGRAM_PATH')
with open('/tmp/graph_data.json', 'w') as f:
    json.dump(graph_data, f, indent=2)
"

# Check file stats
if [ -f "$DIAGRAM_PATH" ]; then
    DIAGRAM_EXISTS="true"
    DIAGRAM_MTIME=$(stat -c %Y "$DIAGRAM_PATH")
    if [ "$DIAGRAM_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    else
        MODIFIED_DURING_TASK="false"
    fi
else
    DIAGRAM_EXISTS="false"
    MODIFIED_DURING_TASK="false"
fi

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH")
else
    EXPORT_EXISTS="false"
    EXPORT_SIZE="0"
fi

# Load graph data
GRAPH_JSON=$(cat /tmp/graph_data.json 2>/dev/null || echo "{}")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "diagram_exists": $DIAGRAM_EXISTS,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "graph_data": $GRAPH_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"