#!/bin/bash
# Export script for agile_user_story_map

echo "=== Exporting User Story Map Result ==="

DISPLAY=:1 import -window root /tmp/storymap_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/foodrescue_storymap.drawio"
PNG_FILE="/home/ga/Desktop/foodrescue_storymap.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check File Existence & Timestamp
FILE_EXISTS="false"
FILE_MODIFIED_AFTER_START="false"
PNG_EXISTS="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Python script to analyze the spatial layout and content
# This extracts shapes, text, colors, and coordinates
python3 << 'PYEOF' > /tmp/storymap_analysis.json 2>/dev/null || true
import json
import re
import os
import base64
import zlib
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/foodrescue_storymap.drawio"
result = {
    "shapes": [],
    "backbone_candidates": [],
    "story_candidates": [],
    "separators": [],
    "error": None
}

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        # Try raw deflate
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        # Try URL encoded
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

def extract_text(cell):
    val = cell.get('value', '')
    # Strip HTML
    clean = re.sub(r'<[^>]+>', ' ', val)
    return clean.strip()

def get_geometry(cell):
    geo = cell.find('mxGeometry')
    if geo is not None:
        try:
            return {
                'x': float(geo.get('x', 0)),
                'y': float(geo.get('y', 0)),
                'width': float(geo.get('width', 0)),
                'height': float(geo.get('height', 0))
            }
        except ValueError:
            pass
    return None

if not os.path.exists(filepath):
    result["error"] = "File not found"
else:
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        all_cells = []
        
        # Handle compression
        diagrams = root.findall('diagram')
        for d in diagrams:
            if d.text:
                expanded = decompress_diagram(d.text)
                if expanded is not None:
                    all_cells.extend(list(expanded.iter('mxCell')))
            else:
                # Uncompressed format usually
                all_cells.extend(list(d.iter('mxCell')))
        
        # Fallback for plain files
        if not all_cells:
            all_cells = list(root.iter('mxCell'))

        for cell in all_cells:
            style = (cell.get('style') or '').lower()
            text = extract_text(cell)
            geo = get_geometry(cell)
            
            if cell.get('vertex') == '1':
                shape_data = {
                    'text': text,
                    'style': style,
                    'geo': geo
                }
                
                # Identify Backbone (Blue)
                # Blue hex codes or keywords: blue, #dae8fc, #6c8ebf
                if 'blue' in style or '#dae8fc' in style or '#6c8ebf' in style:
                    shape_data['type'] = 'activity'
                    result['backbone_candidates'].append(shape_data)
                
                # Identify Stories (Yellow)
                # Yellow hex codes: yellow, #fff2cc, #d6b656
                elif 'yellow' in style or '#fff2cc' in style or '#d6b656' in style:
                    shape_data['type'] = 'story'
                    result['story_candidates'].append(shape_data)
                
                # Identify Separator Line (often a vertex with line style, or just a very wide rectangle)
                elif 'line' in style or (geo and geo['width'] > 300 and geo['height'] < 20):
                     shape_data['type'] = 'separator'
                     result['separators'].append(shape_data)
                
                result['shapes'].append(shape_data)
            
            # Lines drawn with edge tool
            elif cell.get('edge') == '1':
                 # Sometimes users draw the separator as an edge
                 if not text: # Separators usually have no text or "MVP"
                     geo = get_geometry(cell) # Edges store points differently usually, but let's check basic
                     # Edge geometry is complex (sourcePoint, targetPoint), skip for now unless needed
                     pass

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED_AFTER_START,
    "png_exists": $PNG_EXISTS,
    "analysis_path": "/tmp/storymap_analysis.json"
}
EOF

# Merge python analysis into result
if [ -f /tmp/storymap_analysis.json ]; then
    jq -s '.[0] + .[1]' "$TEMP_JSON" /tmp/storymap_analysis.json > /tmp/task_result.json
else
    mv "$TEMP_JSON" /tmp/task_result.json
fi

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"