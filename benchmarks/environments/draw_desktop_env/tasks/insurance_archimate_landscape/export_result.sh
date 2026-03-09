#!/bin/bash
# Do NOT use set -e to prevent early exit on grep misses

echo "=== Exporting insurance_archimate_landscape results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Define File Paths
DRAWIO_FILE="/home/ga/Desktop/claims_architecture.drawio"
PNG_FILE="/home/ga/Desktop/claims_architecture.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Check File Existence and Modification
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found draw.io file: $FILE_SIZE bytes"
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    echo "Found PNG file: $PNG_SIZE bytes"
fi

# 4. Parse draw.io XML Content (Handling Compression)
# We use Python to handle the inflation of compressed XML content common in draw.io files
python3 << 'PYEOF' > /tmp/archimate_analysis.json 2>/dev/null || true
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/claims_architecture.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "archimate_shapes_count": 0,
    "has_business_layer": False,
    "has_app_layer": False,
    "has_tech_layer": False,
    "text_content": [],
    "error": None
}

def decompress_diagram(content):
    """Decompress draw.io diagram data (Deflate + Base64)"""
    if not content: return None
    try:
        # Try raw base64+inflate
        decoded = base64.b64decode(content)
        return zlib.decompress(decoded, -15) # -15 for raw deflate
    except:
        pass
    try:
        # Try URL decoding (sometimes used)
        decoded = unquote(content)
        if decoded.strip().startswith('<'):
            return decoded.encode('utf-8')
    except:
        pass
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Draw.io files can have multiple pages, usually inside <diagram> tags
        diagrams = root.findall('diagram')
        
        all_cells = []
        
        for d in diagrams:
            # Diagram content might be compressed in text node
            if d.text and d.text.strip():
                decompressed_xml = decompress_diagram(d.text.strip())
                if decompressed_xml:
                    d_root = ET.fromstring(decompressed_xml)
                    all_cells.extend(d_root.findall('.//mxCell'))
            # Or inline in mxGraphModel
            all_cells.extend(d.findall('.//mxCell'))
            
        # Also check direct mxGraphModel under root (uncompressed format)
        all_cells.extend(root.findall('.//mxCell'))
        
        # Analyze cells
        for cell in all_cells:
            style = (cell.get('style') or '').lower()
            value = (cell.get('value') or '').lower()
            
            # Count Shapes vs Edges
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                result["text_content"].append(value)
                
                # Check for ArchiMate style
                # ArchiMate shapes typically have 'archimate' in style string
                # e.g. "mxgraph.archimate3.business.business_actor"
                if 'archimate' in style:
                    result["archimate_shapes_count"] += 1
                    
                # Heuristic for layers based on standard colors or ArchiMate types
                if 'business' in style or '#ffffcc' in style or '#eab65c' in style:
                    result["has_business_layer"] = True
                if 'application' in style or '#b5ffff' in style or '#87f2ff' in style:
                    result["has_app_layer"] = True
                if 'technology' in style or '#c9fcd6' in style or '#82f7a8' in style:
                    result["has_tech_layer"] = True
                    
            elif cell.get('edge') == '1':
                result["num_edges"] += 1

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

print(json.dumps(result))
PYEOF

# 5. Create Final Result JSON
# Merge shell variables and Python analysis
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/archimate_analysis.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="