#!/bin/bash
echo "=== Exporting UBO Task Result ==="

export DISPLAY=:1
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Diagrams/omniverse_structure.drawio"
PDF_FILE="/home/ga/Diagrams/exports/omniverse_ubo_map.pdf"

# 1. Take Final Screenshot (Evidence of work)
scrot /tmp/task_final.png

# 2. Check File Existence and Timestamps
DRAWIO_EXISTS=false
PDF_EXISTS=false
FILE_MODIFIED=false

if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS=true
    # Check modification time against task start
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED=true
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS=true
fi

# 3. Parse Draw.io XML Content
# We use a python script to handle potentially compressed XML (deflate/base64)
# and extract the graph data for the verifier.

cat > /tmp/parse_drawio.py << 'EOF'
import sys
import xml.etree.ElementTree as ET
import urllib.parse
import base64
import zlib
import json
import re

def decode_mxfile(xml_content):
    try:
        # Check if raw XML
        if b"<mxGraphModel" in xml_content and b"<root>" in xml_content:
            return xml_content
        
        # Try to parse as mxfile
        tree = ET.fromstring(xml_content)
        if tree.tag == 'mxfile':
            diagram = tree.find('diagram')
            if diagram is not None and diagram.text:
                # Decode: Base64 -> Inflate (drop header) -> UrlDecode
                data = base64.b64decode(diagram.text)
                xml_str = zlib.decompress(data, -15).decode('utf-8')
                return urllib.parse.unquote(xml_str)
    except Exception as e:
        sys.stderr.write(f"Decoding error: {e}\n")
        return None
    return xml_content

file_path = sys.argv[1]
try:
    with open(file_path, 'rb') as f:
        raw_content = f.read()
    
    xml_content = decode_mxfile(raw_content)
    if not xml_content:
        print(json.dumps({"error": "Could not decode file"}))
        sys.exit(0)

    # Parse Graph Model
    if isinstance(xml_content, bytes):
        xml_content = xml_content.decode('utf-8')
        
    # Extract text values (labels) and styles
    # Simple regex extraction to avoid complex XML namespace handling
    # We look for value="..." and style="..."
    
    nodes = []
    
    # Simple regex to find cell definitions
    cell_pattern = re.compile(r'<mxCell\s+(.*?)\s*/>')
    attr_pattern = re.compile(r'([a-zA-Z0-9]+)="([^"]*)"')
    
    # Also handle container cells which might interpret differently in standard XML parser
    # Let's rely on standard ET for the decoded content
    root = ET.fromstring(xml_content)
    
    # Find all mxCell
    for cell in root.iter('mxCell'):
        data = {
            "id": cell.get("id"),
            "value": cell.get("value", ""),
            "style": cell.get("style", ""),
            "vertex": cell.get("vertex"),
            "edge": cell.get("edge"),
            "source": cell.get("source"),
            "target": cell.get("target")
        }
        nodes.append(data)

    print(json.dumps({"nodes": nodes}))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

# Run parser
if [ "$DRAWIO_EXISTS" = "true" ]; then
    PARSED_DATA=$(python3 /tmp/parse_drawio.py "$DRAWIO_FILE")
else
    PARSED_DATA='{"nodes": [], "error": "File not found"}'
fi

# 4. Compile Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "drawio_exists": $DRAWIO_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "parsed_data": $PARSED_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Cleanup and Permission Fix
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"