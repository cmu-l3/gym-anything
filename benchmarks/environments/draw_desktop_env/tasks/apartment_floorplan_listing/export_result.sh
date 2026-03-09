#!/bin/bash
# Do NOT use set -e

echo "=== Exporting apartment_floorplan_listing results ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
DRAWIO_PATH="/home/ga/Desktop/apartment_floorplan.drawio"
PNG_PATH="/home/ga/Desktop/apartment_floorplan.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check file existence and stats
DRAWIO_EXISTS="false"
DRAWIO_SIZE=0
DRAWIO_MODIFIED="false"
if [ -f "$DRAWIO_PATH" ]; then
    DRAWIO_EXISTS="true"
    DRAWIO_SIZE=$(stat -c %s "$DRAWIO_PATH" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "$DRAWIO_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DRAWIO_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
fi

# 4. Parse draw.io XML content using Python
# We extract shapes, text, styles to verify content without relying solely on screenshots
python3 << 'PYEOF' > /tmp/floorplan_analysis.json
import json
import re
import os
import base64
import zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/apartment_floorplan.drawio"
result = {
    "shape_count": 0,
    "edge_count": 0,
    "labels": [],
    "floorplan_shapes": 0,
    "furniture_count": 0,
    "door_count": 0,
    "window_count": 0,
    "styles": [],
    "title_found": False,
    "dimensions_found": 0,
    "room_labels_found": 0
}

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        # draw.io often uses base64 -> zlib (raw deflate)
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        # Sometimes it's just URL encoded xml
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Handle compressed diagrams (mxfile -> diagram -> mxGraphModel)
        # or uncompressed (mxfile -> diagram -> mxGraphModel directly in text?)
        # Standard draw.io saves usually have <diagram>...</diagram> containing compressed data
        
        all_cells = []
        
        # Check for pages
        diagrams = root.findall('diagram')
        for diag in diagrams:
            if diag.text:
                xml_root = decompress_diagram(diag.text)
                if xml_root is not None:
                    all_cells.extend(list(xml_root.iter('mxCell')))
            else:
                # Uncompressed diagram structure
                all_cells.extend(list(diag.iter('mxCell')))
                
        # If no diagrams found, maybe it's a direct mxGraphModel (older formats)
        if not diagrams:
            all_cells.extend(list(root.iter('mxCell')))

        # Room keywords to check
        room_keywords = ['foyer', 'entry', 'living', 'dining', 'kitchen', 'master', 'bedroom', 'bath', 'closet']
        
        for cell in all_cells:
            val = str(cell.get('value', ''))
            style = str(cell.get('style', '')).lower()
            vertex = cell.get('vertex')
            edge = cell.get('edge')
            
            # Clean HTML from label
            clean_val = re.sub(r'<[^>]+>', ' ', val).lower().strip()
            
            if vertex == '1':
                result["shape_count"] += 1
                result["styles"].append(style)
                
                # Check for floorplan specific shapes
                if 'floorplan' in style or 'wall' in style:
                    result["floorplan_shapes"] += 1
                
                # Check for doors/windows/furniture via style
                if 'door' in style or 'opening' in style:
                    result["door_count"] += 1
                if 'window' in style:
                    result["window_count"] += 1
                if 'bed' in style or 'chair' in style or 'sofa' in style or 'table' in style or \
                   'toilet' in style or 'sink' in style or 'bath' in style or 'shower' in style or \
                   'desk' in style or 'dresser' in style or 'cabinet' in style or 'refrigerator' in style or 'stove' in style:
                    result["furniture_count"] += 1
                    
                # Store label if meaningful
                if clean_val:
                    result["labels"].append(clean_val)
                    
                    # Check for title block content
                    if 'mima' in clean_val or '1,150' in clean_val or '38f' in clean_val:
                        result["title_found"] = True
                        
                    # Check for dimensions (e.g., 14' x 12')
                    if re.search(r'\d+[\'"]?\s*[xX*]\s*\d+[\'"]?', clean_val):
                        result["dimensions_found"] += 1
                        
                    # Check for room names
                    for kw in room_keywords:
                        if kw in clean_val:
                            result["room_labels_found"] += 1
                            break
                            
            elif edge == '1':
                result["edge_count"] += 1

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 5. Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_size": $DRAWIO_SIZE,
    "drawio_modified": $DRAWIO_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/floorplan_analysis.json)
}
EOF

# 6. Cleanup
rm -f /tmp/floorplan_analysis.json

echo "Result saved to /tmp/task_result.json"