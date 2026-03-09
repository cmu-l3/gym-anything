#!/bin/bash
echo "=== Exporting Film Set Lighting Plot Results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
DRAWIO_PATH="/home/ga/Diagrams/lighting_plot_scene54.drawio"
PDF_PATH="/home/ga/Diagrams/lighting_plot_scene54.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze Files with Python
# We do this inside the container to handle file parsing locally before exporting JSON
python3 << PY_EOF
import os
import json
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import re

drawio_path = "$DRAWIO_PATH"
pdf_path = "$PDF_PATH"
task_start = int("$TASK_START")

result = {
    "drawio_exists": False,
    "pdf_exists": False,
    "drawio_fresh": False,
    "pdf_fresh": False,
    "shape_count": 0,
    "text_content": "",
    "has_legend": False,
    "has_cabling": False,
    "keywords_found": []
}

def decode_drawio(content):
    """Decompresses draw.io XML content"""
    try:
        # Standard draw.io compression: URL encoded -> Base64 -> Deflate (no header)
        decoded = base64.b64decode(content)
        xml_str = zlib.decompress(decoded, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        return None

if os.path.exists(drawio_path):
    result["drawio_exists"] = True
    if os.path.getmtime(drawio_path) > task_start:
        result["drawio_fresh"] = True
    
    try:
        tree = ET.parse(drawio_path)
        root = tree.getroot()
        
        # Draw.io files can be plain XML or compressed inside <diagram> tags
        full_text = ""
        shapes = 0
        edges = 0
        
        # Check standard XML structure
        if root.tag == 'mxfile':
            for diagram in root.findall('diagram'):
                if diagram.text:
                    # Try to decode compressed content
                    xml_content = decode_drawio(diagram.text)
                    if xml_content:
                        diag_tree = ET.fromstring(xml_content)
                        # Count shapes in decompressed content
                        cells = diag_tree.findall(".//mxCell")
                        shapes += len([c for c in cells if c.get('vertex') == '1'])
                        edges += len([c for c in cells if c.get('edge') == '1'])
                        # Extract text
                        for cell in cells:
                            val = cell.get('value', '')
                            full_text += val + " "
                else:
                    # Fallback for uncompressed
                    cells = diagram.findall(".//mxCell")
                    shapes += len([c for c in cells if c.get('vertex') == '1'])
                    edges += len([c for c in cells if c.get('edge') == '1'])
                    for cell in cells:
                        val = cell.get('value', '')
                        full_text += val + " "
                        
        result["shape_count"] = shapes
        result["text_content"] = full_text.lower()
        
        # Heuristics
        if "legend" in result["text_content"]:
            result["has_legend"] = True
            
        if edges >= 5: # Assuming at least 5 power cables
            result["has_cabling"] = True
            
        # Check keywords
        keywords = ["l1", "l2", "l3", "l4", "l5", "skypanel", "fresnel", "source 4", "detective", "suspect", "distro"]
        for kw in keywords:
            if kw in result["text_content"]:
                result["keywords_found"].append(kw)
                
    except Exception as e:
        print(f"Error parsing drawio: {e}")

if os.path.exists(pdf_path):
    result["pdf_exists"] = True
    if os.path.getmtime(pdf_path) > task_start:
        result["pdf_fresh"] = True

# Save result to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PY_EOF

# 4. Move result to accessible location
# Use cat to avoid permission issues if they arise
cat /tmp/task_result.json > /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "Result exported to /tmp/final_result.json"