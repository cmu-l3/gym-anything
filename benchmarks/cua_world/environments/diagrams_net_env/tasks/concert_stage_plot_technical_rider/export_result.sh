#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Basic File Checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Diagrams/neon_velvet_rider.drawio"
PDF_FILE="/home/ga/Diagrams/neon_velvet_rider.pdf"

DRAWIO_EXISTS="false"
PDF_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
fi

# 2. Advanced Analysis with Python
# We interpret the XML structure to find text labels and geometry
python3 << 'PYEOF'
import sys
import zlib
import base64
import json
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

file_path = "/home/ga/Diagrams/neon_velvet_rider.drawio"
output_json = "/tmp/task_result.json"

result = {
    "drawio_exists": False,
    "pdf_exists": False,
    "text_content": [],
    "shapes": []
}

# Load environment vars passed from bash
result["drawio_exists"] = (os.environ.get("DRAWIO_EXISTS") == "true")
result["pdf_exists"] = (os.environ.get("PDF_EXISTS") == "true")
result["file_created_during_task"] = (os.environ.get("FILE_CREATED_DURING_TASK") == "true")

def decode_mxfile(root):
    """Decodes compressed diagram data if present."""
    xml_content = ""
    # Check for compressed data in <diagram> tag
    diagram = root.find("diagram")
    if diagram is not None and diagram.text:
        try:
            # Decode: Base64 -> Inflate (no header) -> URL Decode
            # Note: draw.io usually does Deflate (raw)
            data = base64.b64decode(diagram.text)
            xml_content = zlib.decompress(data, -15).decode('utf-8')
            xml_content = unquote(xml_content)
            return ET.fromstring(xml_content)
        except Exception as e:
            # Maybe it's not compressed?
            return root
    return root

if result["drawio_exists"]:
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # If it's a compressed mxfile, decode it
        if root.tag == "mxfile":
            graph_model = decode_mxfile(root)
        else:
            graph_model = root

        # Extract text and geometry
        # Looking for <mxCell value="..." style="..." ...> <mxGeometry x="..." y="..." .../> </mxCell>
        for cell in graph_model.findall(".//mxCell"):
            val = cell.get("value", "")
            style = cell.get("style", "")
            geometry = cell.find("mxGeometry")
            
            # Text content
            if val:
                # Basic HTML tag stripping if needed, but raw search usually fine
                result["text_content"].append(val)
            
            # Geometry
            if geometry is not None:
                x = float(geometry.get("x", 0))
                y = float(geometry.get("y", 0))
                
                # Try to identify what this shape is based on text value
                # Normalize text for easier matching
                val_lower = val.lower()
                shape_type = "unknown"
                if "drum" in val_lower: shape_type = "Drums"
                elif "bass" in val_lower: shape_type = "Bass"
                elif "guitar" in val_lower: shape_type = "Guitar"
                elif "key" in val_lower: shape_type = "Keys"
                elif "vocal" in val_lower or "lead" in val_lower: shape_type = "Vocals"
                elif "monitor" in val_lower: shape_type = "Monitor"
                
                if shape_type != "unknown":
                    result["shapes"].append({
                        "type": shape_type,
                        "x": x,
                        "y": y,
                        "raw_text": val
                    })
                    
    except Exception as e:
        result["error"] = str(e)

with open(output_json, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# 3. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Analysis complete. JSON saved to /tmp/task_result.json"