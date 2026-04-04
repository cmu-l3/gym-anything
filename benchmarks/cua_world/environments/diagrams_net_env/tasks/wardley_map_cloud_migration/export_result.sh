#!/bin/bash
echo "=== Exporting Wardley Map Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check PDF Export
PDF_PATH="/home/ga/Diagrams/exports/wardley_map_cloud_migration.pdf"
PDF_EXISTS="false"
PDF_SIZE=0
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
fi

# 3. Python script to analyze the .drawio XML content
# draw.io files are often compressed XML. This script handles unzipping and parsing.
cat > /tmp/analyze_drawio.py << 'EOF'
import sys
import zlib
import base64
import xml.etree.ElementTree as ET
import urllib.parse
import json
import os

file_path = "/home/ga/Diagrams/wardley_map.drawio"
start_time_file = "/tmp/task_start_time.txt"

result = {
    "valid_xml": False,
    "total_shapes": 0,
    "total_edges": 0,
    "labels_found": [],
    "colors_found": [],
    "dashed_arrows": 0,
    "modified_after_start": False,
    "error": None
}

try:
    # Check modification time
    if os.path.exists(start_time_file):
        with open(start_time_file, 'r') as f:
            start_time = int(f.read().strip())
        mtime = int(os.path.getmtime(file_path))
        if mtime > start_time:
            result["modified_after_start"] = True

    tree = ET.parse(file_path)
    root = tree.getroot()
    
    # Handle draw.io compressed format if needed
    # Usually <mxfile><diagram>ENCODED_STRING</diagram></mxfile>
    diagram_node = root.find('diagram')
    if diagram_node is not None and diagram_node.text:
        try:
            # Decode: Base64 -> Inflate (no header) -> URL Decode
            compressed = base64.b64decode(diagram_node.text)
            xml_str = zlib.decompress(compressed, -15).decode('utf-8')
            xml_str = urllib.parse.unquote(xml_str)
            root = ET.fromstring(xml_str)
        except Exception as e:
            # Maybe it's not compressed, continue with original root if it has children
            pass

    # Now iterate through cells
    # draw.io structure: root -> mxCell
    # Vertices (shapes) have vertex="1"
    # Edges (lines) have edge="1"
    
    for cell in root.iter('mxCell'):
        style = cell.get('style', '')
        value = cell.get('value', '')
        
        # Check Vertices
        if cell.get('vertex') == '1':
            result["total_shapes"] += 1
            if value and not value.isspace():
                # Clean label (remove HTML tags if present)
                clean_val = ''.join(ET.fromstring(f'<r>{value}</r>').itertext()) if '<' in value else value
                result["labels_found"].append(clean_val.strip())
            
            # Extract colors (fillColor)
            if 'fillColor=' in style:
                # simple extraction
                parts = style.split(';')
                for p in parts:
                    if p.startswith('fillColor='):
                        color = p.split('=')[1]
                        if color != 'none':
                            result["colors_found"].append(color)

        # Check Edges
        elif cell.get('edge') == '1':
            result["total_edges"] += 1
            # Check for dashed evolution arrows (style dashed=1 or dashed=true)
            if 'dashed=1' in style or 'dashed=true' in style:
                # Evolution arrows are usually thicker, check for strokeWidth if needed
                result["dashed_arrows"] += 1

    result["valid_xml"] = True
    result["colors_found"] = list(set(result["colors_found"])) # unique

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run analysis
ANALYSIS_JSON=$(python3 /tmp/analyze_drawio.py)

# 4. Construct Final Result JSON
cat > /tmp/task_result.json << EOF
{
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $ANALYSIS_JSON
}
EOF

# Output for debugging
cat /tmp/task_result.json
echo "=== Export Complete ==="