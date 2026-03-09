#!/bin/bash
echo "=== Exporting hydraulic_forklift_circuit result ==="

# Paths
DRAWIO_FILE="/home/ga/Desktop/forklift_hydraulic.drawio"
PNG_FILE="/home/ga/Desktop/forklift_hydraulic.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check files existence and timestamp
FILE_EXISTS="false"
PNG_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# 3. Python script to parse the drawio XML (handling compression) and extract metrics
# We need to detect if they used the correct library (styles) and connected things.

python3 << 'EOF' > /tmp/task_result.json
import sys
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

drawio_path = "/home/ga/Desktop/forklift_hydraulic.drawio"
task_start = int(os.environ.get('TASK_START', 0))

result = {
    "file_exists": False,
    "file_modified": False,
    "png_exists": False,
    "shape_count": 0,
    "edge_count": 0,
    "fluid_power_shapes": 0,
    "labels_found": [],
    "components_found": {
        "pump": False,
        "cylinder": False,
        "valve": False,
        "tank": False,
        "motor": False,
        "filter": False
    },
    "connectivity_score": 0
}

# Check PNG
if os.path.exists("/home/ga/Desktop/forklift_hydraulic.png"):
    result["png_exists"] = True

if os.path.exists(drawio_path):
    result["file_exists"] = True
    if os.path.getmtime(drawio_path) > task_start:
        result["file_modified"] = True

    try:
        # Parse XML (draw.io files are XML, possibly compressed)
        tree = ET.parse(drawio_path)
        root = tree.getroot()

        # Helper to get cells
        cells = []
        
        # Check for compressed content in <diagram> tags
        diagrams = root.findall('diagram')
        for d in diagrams:
            content = d.text
            if content:
                # Try inflate
                try:
                    decoded = base64.b64decode(content)
                    xml_str = zlib.decompress(decoded, -15).decode('utf-8')
                    # Parse inner XML
                    inner = ET.fromstring(f"<root>{xml_str}</root>") # wrap to ensure root
                    cells.extend(inner.findall(".//mxCell"))
                except Exception as e:
                    # Might be URL encoded
                    try:
                        decoded = unquote(content)
                        inner = ET.fromstring(f"<root>{decoded}</root>")
                        cells.extend(inner.findall(".//mxCell"))
                    except:
                        pass
        
        # Also check standard structure (uncompressed)
        cells.extend(root.findall(".//mxCell"))

        # Analyze cells
        for cell in cells:
            style = (cell.get('style') or "").lower()
            value = (cell.get('value') or "").lower()
            
            # Count shapes (vertex) vs edges
            if cell.get('vertex') == '1':
                result["shape_count"] += 1
                
                # Check for Fluid Power library usage
                # Styles often look like: "shape=mxgraph.fluid_power.pump..."
                # or "verticalLabelPosition=...;...heuristic..."
                if "fluid_power" in style or "hydraulic" in style or "valves" in style or "pid" in style:
                    result["fluid_power_shapes"] += 1
                
                # Check labels/values
                if value:
                    result["labels_found"].append(value)
                    if "pump" in value: result["components_found"]["pump"] = True
                    if "cylinder" in value: result["components_found"]["cylinder"] = True
                    if "valve" in value: result["components_found"]["valve"] = True
                    if "tank" in value or "reservoir" in value: result["components_found"]["tank"] = True
                    if "motor" in value: result["components_found"]["motor"] = True
                    if "filter" in value: result["components_found"]["filter"] = True

                # Fallback: check style names for component types if labels are missing
                if "pump" in style: result["components_found"]["pump"] = True
                if "cylinder" in style: result["components_found"]["cylinder"] = True
                if "valve" in style: result["components_found"]["valve"] = True
                if "tank" in style or "reservoir" in style: result["components_found"]["tank"] = True
                if "motor" in style: result["components_found"]["motor"] = True
                if "filter" in style: result["components_found"]["filter"] = True

            elif cell.get('edge') == '1':
                result["edge_count"] += 1
                if cell.get('source') and cell.get('target'):
                    result["connectivity_score"] += 1

    except Exception as e:
        print(f"Error parsing drawio: {e}", file=sys.stderr)

print(json.dumps(result))
EOF

# Move result to safe location
mv /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "=== Export complete ==="