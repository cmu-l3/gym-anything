#!/bin/bash
echo "=== Exporting Genogram Task Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/genogram.drawio"
PNG_FILE="/home/ga/Desktop/genogram.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and timestamps
DRAWIO_EXISTS="false"
DRAWIO_CREATED_DURING="false"
if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DRAWIO_CREATED_DURING="true"
    fi
fi

PNG_EXISTS="false"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Run Python script to parse the draw.io XML structure
# This script extracts shapes, positions (generations), styles (gender/disease), and labels.
python3 << 'PYEOF' > /tmp/genogram_analysis.json 2>/dev/null || true
import json
import os
import re
import base64
import zlib
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/genogram.drawio"
result = {
    "people": {},
    "generations": {"I": [], "II": [], "III": []},
    "shapes_count": 0,
    "edges_count": 0,
    "lines_count": 0,
    "error": None
}

def decompress_diagram(content):
    if not content: return None
    # Try base64+deflate
    try:
        decoded = base64.b64decode(content)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except: pass
    # Try URL decode
    try:
        decoded = unquote(content)
        if decoded.strip().startswith('<'): return decoded
    except: pass
    return content

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Handle compressed diagram
        diagram_node = root.find('diagram')
        if diagram_node is not None:
            raw_content = diagram_node.text
            xml_content = decompress_diagram(raw_content)
            if xml_content:
                # Re-parse the inner XML
                root = ET.fromstring(xml_content)

        # Parse cells
        cells = root.findall(".//mxCell")
        
        # We need to map labels to properties
        # Labels might be in 'value' attribute
        
        people_map = {}
        
        for cell in cells:
            val = (cell.get('value') or "").strip()
            style = (cell.get('style') or "").lower()
            geo = cell.find('mxGeometry')
            
            is_vertex = cell.get('vertex') == '1'
            is_edge = cell.get('edge') == '1'
            
            if is_vertex:
                result["shapes_count"] += 1
                
                # Check for "Line" shapes (potential deceased markers)
                if 'line' in style or 'cross' in style or 'shape=line' in style:
                    result["lines_count"] += 1

                # Clean label (remove HTML)
                clean_label = re.sub(r'<[^>]+>', '', val).strip()
                
                # Identify person
                # We look for names in the label
                names = ["Arthur", "Betty", "Charles", "Diana", "Edward", "Alice", "Frank"]
                found_name = None
                for name in names:
                    if name.lower() in clean_label.lower():
                        found_name = name
                        break
                
                if found_name:
                    # Analyze Style
                    # Gender: Rect vs Ellipse
                    shape_type = "unknown"
                    if 'ellipse' in style:
                        shape_type = "ellipse"
                    elif 'rect' in style or 'process' in style or not 'shape=' in style: 
                        # Default shape is often rect
                        shape_type = "rectangle"
                    
                    # Disease: Fill Color
                    # Check for fillColor=... 
                    # If missing, it's often white/transparent. If present and not white/none -> Filled
                    fill = "none"
                    if 'fillcolor' in style:
                        # Extract color
                        match = re.search(r'fillcolor=([^;]+)', style)
                        if match:
                            c = match.group(1).lower()
                            if c not in ['none', 'white', '#ffffff', 'transparent']:
                                fill = "filled"
                            else:
                                fill = "white"
                    
                    # Coordinates for Generation check
                    y_pos = 0
                    if geo is not None:
                        y_pos = float(geo.get('y') or 0)
                    
                    # Text content (for '?' check)
                    text_content = clean_label
                    
                    people_map[found_name] = {
                        "shape": shape_type,
                        "fill": fill,
                        "y": y_pos,
                        "text": text_content
                    }

            if is_edge:
                result["edges_count"] += 1

        result["people"] = people_map
        
        # Sort generations by Y coordinate
        # Group Y coords into clusters
        y_coords = [p['y'] for p in people_map.values()]
        if y_coords:
            y_coords.sort()
            # Simple clustering: if gap > 50px, new generation
            # But simpler: just normalize relative to min/max
            
            # We expect 3 distinct bands of Y coordinates
            # Let's just pass raw Y to verifier to check order I < II < III
            pass

    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Combine into result JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_created_during_task": $DRAWIO_CREATED_DURING,
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/genogram_analysis.json)
}
EOF

# Save safely
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"