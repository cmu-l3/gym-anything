#!/bin/bash
echo "=== Exporting Tech Radar Result ==="

# 1. Capture Final State Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Diagrams/tech_radar_Q4_2024.drawio"
TEMPLATE_FILE="/home/ga/Diagrams/tech_radar_template.drawio"

# Determine which file the user saved to (they might have overwritten template)
ACTUAL_FILE=""
if [ -f "$DRAWIO_FILE" ]; then
    ACTUAL_FILE="$DRAWIO_FILE"
elif [ -f "$TEMPLATE_FILE" ]; then
    # Check if template was modified
    TEMPLATE_MTIME=$(stat -c %Y "$TEMPLATE_FILE" 2>/dev/null || echo "0")
    if [ "$TEMPLATE_MTIME" -gt "$TASK_START" ]; then
        ACTUAL_FILE="$TEMPLATE_FILE"
    fi
fi

FILE_MODIFIED="false"
SHAPE_COUNT=0
LABELS_JSON="[]"
COLORS_JSON="[]"

if [ -n "$ACTUAL_FILE" ]; then
    FILE_MODIFIED="true"
    
    # Parse the XML to extract labels and styles (fillColor)
    # We use a python script to parse the XML robustly
    python3 -c "
import xml.etree.ElementTree as ET
import json
import urllib.parse
import base64
import zlib
import re

try:
    tree = ET.parse('$ACTUAL_FILE')
    root = tree.getroot()
    
    labels = []
    colors = set()
    shape_count = 0
    
    # Function to decode compressed draw.io content if needed
    def parse_mxfile(root):
        cells = []
        # Check if compressed
        diagrams = root.findall('diagram')
        if not diagrams:
            return root.findall('.//mxCell')
            
        for d in diagrams:
            if d.text:
                try:
                    # Decode: Base64 -> Inflate -> URLDecode
                    # Note: draw.io usually does Deflate then Base64
                    data = base64.b64decode(d.text)
                    xml_str = zlib.decompress(data, -15).decode('utf-8')
                    xml_str = urllib.parse.unquote(xml_str)
                    dom = ET.fromstring(xml_str)
                    cells.extend(dom.findall('.//mxCell'))
                except:
                    # Fallback for uncompressed
                    cells.extend(root.findall('.//mxCell'))
            else:
                cells.extend(root.findall('.//mxCell'))
        return cells

    # Handle standard uncompressed XML first (easier)
    if root.find('.//diagram') is None:
        cells = root.findall('.//mxCell')
    else:
        # Try to parse diagram node
        cells = parse_mxfile(root)

    for cell in cells:
        val = cell.get('value', '')
        style = cell.get('style', '')
        
        # Count shapes (vertices that are not empty group parents)
        if cell.get('vertex') == '1':
            shape_count += 1
            if val:
                # Remove HTML tags if present for text checking
                clean_val = re.sub('<[^<]+?>', '', val).strip()
                if clean_val:
                    labels.append(clean_val)
            
            # Extract fill colors
            color_match = re.search(r'fillColor=([^;]+)', style)
            if color_match:
                c = color_match.group(1)
                if c != 'none' and c != '#FFFFFF':
                    colors.add(c)

    print(json.dumps({
        'shape_count': shape_count,
        'labels': labels,
        'colors': list(colors)
    }))
except Exception as e:
    print(json.dumps({'error': str(e), 'shape_count': 0, 'labels': [], 'colors': []}))
" > /tmp/xml_analysis.json

    SHAPE_COUNT=$(jq '.shape_count' /tmp/xml_analysis.json)
    LABELS_JSON=$(jq '.labels' /tmp/xml_analysis.json)
    COLORS_JSON=$(jq '.colors' /tmp/xml_analysis.json)
fi

# 3. Check PNG Export
PNG_FILE="/home/ga/Diagrams/exports/tech_radar_Q4_2024.png"
PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# 4. Generate Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "actual_file_path": "$ACTUAL_FILE",
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "shape_count": $SHAPE_COUNT,
    "extracted_labels": $LABELS_JSON,
    "extracted_colors": $COLORS_JSON,
    "initial_shape_count": $(cat /tmp/initial_shape_count.txt 2>/dev/null || echo 0)
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="