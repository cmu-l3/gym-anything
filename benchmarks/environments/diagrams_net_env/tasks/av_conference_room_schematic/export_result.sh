#!/bin/bash
echo "=== Exporting AV Schematic Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
DIAGRAM_PATH="/home/ga/Diagrams/av_schematic.drawio"
PDF_PATH="/home/ga/Diagrams/av_schematic.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Python script to parse the .drawio XML (handles compression)
# We embed this to avoid dependency issues on the host
cat > /tmp/parse_drawio.py << 'PYEOF'
import sys
import os
import zlib
import base64
import json
import urllib.parse
import xml.etree.ElementTree as ET

def decode_drawio(content):
    """Decompresses draw.io XML content if needed."""
    try:
        # Check if it's the compressed format
        if not content.strip().startswith('<'):
             # It might be raw base64 or urlencoded
             try:
                 decoded = base64.b64decode(content)
                 return zlib.decompress(decoded, -15).decode('utf-8')
             except:
                 pass
        
        # Standard draw.io compression (mxfile -> diagram -> text)
        tree = ET.fromstring(content)
        if tree.tag == 'mxfile':
            diagram = tree.find('diagram')
            if diagram is not None and diagram.text:
                # Decode: URL decode -> Base64 decode -> Inflate
                data = urllib.parse.unquote(diagram.text)
                data = base64.b64decode(data)
                xml_content = zlib.decompress(data, -15).decode('utf-8')
                return xml_content
        return content # Return original if not compressed
    except Exception as e:
        sys.stderr.write(f"Error decoding: {e}\n")
        return content

def parse_topology(xml_content):
    try:
        # If content is wrapped in <mxGraphModel>, extract it, otherwise parse root
        try:
            root = ET.fromstring(xml_content)
        except ET.ParseError:
            # Wrap in root if fragment
            root = ET.fromstring(f"<root>{xml_content}</root>")

        # Find graph model
        graph = root.find('.//mxGraphModel')
        if graph is None:
            # Might be directly in root if decoded from diagram tag
            graph = root

        # Extract Shapes (Vertices) and Edges
        shapes = {} # id -> {label, type}
        edges = []  # {source_id, target_id, style}

        for cell in graph.findall('.//mxCell'):
            c_id = cell.get('id')
            value = cell.get('value', '').lower()
            style = cell.get('style', '').lower()
            vertex = cell.get('vertex')
            edge = cell.get('edge')
            source = cell.get('source')
            target = cell.get('target')

            if vertex == '1':
                shapes[c_id] = {'label': value, 'style': style}
            
            if edge == '1' and source and target:
                edges.append({
                    'source': source, 
                    'target': target, 
                    'style': style,
                    'value': value
                })

        return shapes, edges
    except Exception as e:
        sys.stderr.write(f"Error parsing topology: {e}\n")
        return {}, []

if __name__ == "__main__":
    file_path = sys.argv[1]
    if not os.path.exists(file_path):
        print(json.dumps({"error": "File not found"}))
        sys.exit(0)

    with open(file_path, 'r') as f:
        content = f.read()

    decoded_xml = decode_drawio(content)
    shapes, edges = parse_topology(decoded_xml)
    
    # Resolve edge IDs to labels
    resolved_edges = []
    for e in edges:
        src = shapes.get(e['source'], {'label': 'unknown'})['label']
        tgt = shapes.get(e['target'], {'label': 'unknown'})['label']
        resolved_edges.append({
            'source_label': src,
            'target_label': tgt,
            'style': e['style']
        })

    result = {
        "file_exists": True,
        "file_size": os.path.getsize(file_path),
        "shapes": list(shapes.values()),
        "edges": resolved_edges
    }
    print(json.dumps(result))
PYEOF

# 4. Check File Existence & Timestamp
FILE_EXISTS=false
FILE_CREATED_DURING_TASK=false
PDF_EXISTS=false

if [ -f "$DIAGRAM_PATH" ]; then
    FILE_EXISTS=true
    MTIME=$(stat -c %Y "$DIAGRAM_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS=true
fi

# 5. Execute Python Parser
PARSED_DATA="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    PARSED_DATA=$(python3 /tmp/parse_drawio.py "$DIAGRAM_PATH")
fi

# 6. Check if App Running
APP_RUNNING=$(pgrep -f "drawio" > /dev/null && echo "true" || echo "false")

# 7. Construct Final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "pdf_exists": $PDF_EXISTS,
    "app_running": $APP_RUNNING,
    "diagram_data": $PARSED_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 8. Cleanup and Permissions
chmod 666 /tmp/task_result.json
rm -f /tmp/parse_drawio.py

echo "Export complete. Result:"
cat /tmp/task_result.json