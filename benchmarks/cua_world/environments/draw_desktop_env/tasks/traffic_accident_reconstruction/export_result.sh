#!/bin/bash
# Export script for Traffic Accident Reconstruction task

echo "=== Exporting Task Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DRAWIO_FILE="/home/ga/Desktop/accident_reconstruction.drawio"
PNG_FILE="/home/ga/Desktop/accident_reconstruction.png"

# Check file existence and timestamps
DRAWIO_EXISTS="false"
DRAWIO_MODIFIED="false"
if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DRAWIO_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Analyze draw.io XML content using embedded Python
# This extracts text labels, shapes, colors, and rotation info
echo "Analyzing diagram content..."
python3 << 'PYEOF' > /tmp/diagram_analysis.json
import sys
import json
import re
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse

filepath = "/home/ga/Desktop/accident_reconstruction.drawio"
result = {
    "labels": [],
    "shapes": [],
    "has_rotation": False,
    "has_north_arrow": False,
    "unit1_found": False,
    "unit2_found": False,
    "unit1_color": None,
    "unit2_color": None
}

def decode_diagram(root):
    # draw.io often compresses the XML inside the <diagram> tag
    diagram_node = root.find('diagram')
    if diagram_node is not None and diagram_node.text:
        try:
            # Try Base64 + Deflate
            data = base64.b64decode(diagram_node.text)
            xml_data = zlib.decompress(data, -15).decode('utf-8')
            return ET.fromstring(f"<root>{xml_data}</root>")  # Wrap to make valid XML
        except Exception:
            try:
                # Try URL decode
                xml_data = urllib.parse.unquote(diagram_node.text)
                return ET.fromstring(f"<root>{xml_data}</root>")
            except Exception:
                pass
    return root

try:
    tree = ET.parse(filepath)
    root = tree.getroot()
    content_root = decode_diagram(root)
    
    # Iterate through cells
    for cell in content_root.iter('mxCell'):
        value = cell.get('value', '')
        style = cell.get('style', '')
        
        # Clean HTML from labels
        clean_label = re.sub('<[^<]+?>', '', value).strip()
        if clean_label:
            result['labels'].append(clean_label)
        
        # Check styles
        shape_info = {'id': cell.get('id'), 'label': clean_label, 'style': style}
        
        # Check for rotation
        if 'rotation=' in style:
            result['has_rotation'] = True
            
        # Check for colors (Fill color)
        # Blue-ish colors: #0000FF, #DAE8FC (draw.io default blue), blue
        # Red-ish colors: #FF0000, #F8CECC (draw.io default red), red
        
        style_lower = style.lower()
        fill_match = re.search(r'fillcolor=([^;]+)', style_lower)
        fill_color = fill_match.group(1) if fill_match else ""
        
        is_blue = 'blue' in style_lower or '#00' in fill_color or '#dae8fc' in fill_color
        is_red = 'red' in style_lower or '#ff' in fill_color or '#f8cecc' in fill_color
        
        # Check for Unit 1 / Unit 2 labels combined with color
        if 'unit 1' in clean_label.lower():
            result['unit1_found'] = True
            if is_blue: result['unit1_color'] = 'blue'
            elif is_red: result['unit1_color'] = 'red'
            
        if 'unit 2' in clean_label.lower():
            result['unit2_found'] = True
            if is_red: result['unit2_color'] = 'red'
            elif is_blue: result['unit2_color'] = 'blue'
            
        # Check for North Arrow
        # Often has 'shape=mxgraph.arrows' or just text "N" or "North"
        if 'arrow' in style_lower or clean_label.lower() in ['n', 'north']:
            result['has_north_arrow'] = True

        result['shapes'].append(shape_info)
        
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYEOF

# Merge info into final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_modified": $DRAWIO_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $(cat /tmp/diagram_analysis.json)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"