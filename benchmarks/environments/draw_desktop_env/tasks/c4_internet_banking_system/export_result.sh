#!/bin/bash
echo "=== Exporting C4 Banking task results ==="

DRAWIO_FILE="/home/ga/Desktop/c4_banking.drawio"
PNG_FILE="/home/ga/Desktop/c4_banking.png"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0
PNG_EXISTS="false"
PNG_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# Parse the drawio XML to extract content info
# We use Python here because draw.io files are often compressed XML (deflate)
python3 << 'PYEOF' > /tmp/drawio_analysis.json 2>/dev/null || true
import json
import xml.etree.ElementTree as ET
import sys
import base64
import zlib
import re
from urllib.parse import unquote

filepath = "/home/ga/Desktop/c4_banking.drawio"
result = {
    "page_count": 0,
    "page_names": [],
    "shape_labels": [],
    "edge_labels": [],
    "styles": [],
    "has_cylinder": False,
    "error": None
}

def decode_diagram(text):
    if not text: return None
    try:
        # Try base64 + inflate (standard draw.io format)
        decoded = base64.b64decode(text)
        inflated = zlib.decompress(decoded, -15)
        return ET.fromstring(inflated)
    except:
        try:
            # Try URL encoded
            decoded = unquote(text)
            if decoded.strip().startswith('<'):
                return ET.fromstring(decoded)
        except:
            pass
    return None

try:
    tree = ET.parse(filepath)
    root = tree.getroot()
    
    diagrams = root.findall('diagram')
    result['page_count'] = len(diagrams)
    
    all_cells = []
    
    for d in diagrams:
        result['page_names'].append(d.get('name', ''))
        
        # Get content (could be inline or text content)
        content_root = None
        if list(d): # Has children
             # Check for mxGraphModel direct child
             if d.find('mxGraphModel') is not None:
                 content_root = d.find('mxGraphModel').find('root')
        
        if content_root is None and d.text:
            mx_graph = decode_diagram(d.text)
            if mx_graph is not None:
                content_root = mx_graph.find('root')
                
        if content_root is not None:
            all_cells.extend(content_root.findall('mxCell'))

    # Also check root if no diagrams found (uncompressed simple file)
    if not diagrams:
        all_cells.extend(root.findall('.//mxCell'))

    # Analyze cells
    for cell in all_cells:
        val = cell.get('value', '')
        style = cell.get('style', '')
        
        # Clean HTML from value
        val_clean = re.sub(r'<[^>]+>', ' ', val).strip()
        
        if cell.get('vertex') == '1':
            if val_clean: result['shape_labels'].append(val_clean)
            result['styles'].append(style)
            
            # Check for cylinder/database shape
            if 'cylinder' in style.lower() or 'database' in style.lower() or 'datastore' in style.lower():
                result['has_cylinder'] = True
                
        elif cell.get('edge') == '1':
            if val_clean: result['edge_labels'].append(val_clean)

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYEOF

# Combine results into final JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/drawio_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Handle permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="