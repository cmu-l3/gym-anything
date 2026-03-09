#!/bin/bash
echo "=== Exporting Physical Security Design Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
DRAWIO_FILE="/home/ga/Diagrams/security_design.drawio"
PDF_FILE="/home/ga/Diagrams/security_design.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze Results using Python (in-container)
# We parse the XML to count shapes and edges
cat << 'EOF' > /tmp/analyze_diagram.py
import sys
import os
import zlib
import base64
import json
import re
from urllib.parse import unquote
import xml.etree.ElementTree as ET

drawio_path = sys.argv[1]
pdf_path = sys.argv[2]
task_start = float(sys.argv[3])

result = {
    "drawio_exists": False,
    "pdf_exists": False,
    "file_modified": False,
    "shape_counts": {
        "camera": 0,
        "reader": 0,
        "sensor": 0,
        "panel": 0,
        "image": 0
    },
    "edge_count": 0,
    "total_shapes": 0
}

if os.path.exists(pdf_path):
    result["pdf_exists"] = True

if os.path.exists(drawio_path):
    result["drawio_exists"] = True
    if os.path.getmtime(drawio_path) > task_start:
        result["file_modified"] = True
    
    try:
        tree = ET.parse(drawio_path)
        root = tree.getroot()
        
        # Handle compressed diagrams
        # draw.io often wraps content in <diagram> tag with compressed text
        diagram_nodes = root.findall('diagram')
        xml_content = ""
        
        if diagram_nodes:
            # It's a compressed file
            raw_text = diagram_nodes[0].text
            if raw_text:
                try:
                    # Standard draw.io compression: base64 -> zlib -> url-decode
                    decoded = base64.b64decode(raw_text)
                    xml_content = zlib.decompress(decoded, -15).decode('utf-8')
                    # Sometimes it needs url decoding first, but usually base64 handles it
                except:
                    try:
                        # Alternative: url-decode -> base64 -> zlib
                        decoded = base64.b64decode(unquote(raw_text))
                        xml_content = zlib.decompress(decoded, -15).decode('utf-8')
                    except Exception as e:
                        print(f"Decompression error: {e}")
                        xml_content = ""
        else:
            # Uncompressed or plain XML
            xml_content = ET.tostring(root, encoding='utf8').decode('utf8')
            
        if xml_content:
            # Parse the inner XML
            # Wrap in root if it's just a graph model snippet
            if not xml_content.strip().startswith('<'): 
                # Sometimes it decodes to just url-encoded text
                xml_content = unquote(xml_content)
                
            if "<mxGraphModel>" in xml_content:
                # Extract shapes
                # We look for 'value' or 'style' attributes indicating type
                
                # Regex is safer for messy XML fragments than strict parsing
                # Count Cameras
                result["shape_counts"]["camera"] = len(re.findall(r'camera|cctv|video', xml_content, re.IGNORECASE))
                
                # Count Readers
                result["shape_counts"]["reader"] = len(re.findall(r'card.?reader|access|biometric|keypad', xml_content, re.IGNORECASE))
                
                # Count Sensors (Motion/Contact)
                result["shape_counts"]["sensor"] = len(re.findall(r'sensor|motion|detector|contact|reed', xml_content, re.IGNORECASE))
                
                # Count Panel
                result["shape_counts"]["panel"] = len(re.findall(r'panel|control|controller', xml_content, re.IGNORECASE))
                
                # Count Images (Floorplan)
                result["shape_counts"]["image"] = len(re.findall(r'image;', xml_content, re.IGNORECASE))
                
                # Count Edges
                # In draw.io XML, edges usually have edge="1"
                result["edge_count"] = len(re.findall(r'edge="1"', xml_content))
                
                # Total non-edge objects
                result["total_shapes"] = len(re.findall(r'vertex="1"', xml_content))

    except Exception as e:
        print(f"Analysis Failed: {e}")

print(json.dumps(result))
EOF

# Run analysis
ANALYSIS_JSON=$(python3 /tmp/analyze_diagram.py "$DRAWIO_FILE" "$PDF_FILE" "$TASK_START")

# 4. Save to Result File
echo "$ANALYSIS_JSON" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Analysis complete. Result:"
cat /tmp/task_result.json