#!/bin/bash
echo "=== Exporting Gala Dinner Seating Plan results ==="

# Define paths
RESULT_JSON="/tmp/task_result.json"
DRAWIO_FILE="/home/ga/Desktop/gala_seating_plan.drawio"
PNG_FILE="/home/ga/Desktop/gala_seating_plan.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamps
FILE_EXISTS="false"
FILE_MODIFIED="false"
PNG_EXISTS="false"
PNG_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# 3. Python script to analyze the drawio XML structure
# This script handles decompression of the drawio format and counts shapes/attributes.
python3 << 'PYEOF' > /tmp/gala_analysis.json 2>/dev/null
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/gala_seating_plan.drawio"
result = {
    "valid_xml": False,
    "round_table_count": 0,
    "rect_table_count": 0,
    "chair_count": 0,
    "total_shapes": 0,
    "vip_highlight_count": 0,
    "labels_found": [],
    "has_stage": False,
    "has_bar": False
}

def decode_drawio(content):
    """Decompress draw.io XML content."""
    if not content: return None
    # Try raw XML first
    if content.strip().startswith('<'):
        try:
            return ET.fromstring(content)
        except:
            pass
    
    # Try parsing as mxfile/diagram
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        diagram = root.find('diagram')
        if diagram is not None and diagram.text:
            # Decode base64
            data = base64.b64decode(diagram.text)
            # Decompress deflate
            xml_str = zlib.decompress(data, -15).decode('utf-8')
            return ET.fromstring(unquote(xml_str))
        return root # Fallback if uncompressed
    except Exception as e:
        return None

if os.path.exists(filepath):
    try:
        root = decode_drawio(None) # Argument unused since we parse file inside
        if root is not None:
            result["valid_xml"] = True
            
            # Iterate through all cells
            for cell in root.iter('mxCell'):
                style = str(cell.get('style', '')).lower()
                value = str(cell.get('value', '')).lower()
                vertex = cell.get('vertex')
                
                if vertex == '1':
                    result["total_shapes"] += 1
                    
                    # Identify Round Tables (ellipse)
                    if 'ellipse' in style or 'shape=ellipse' in style:
                        # Exclude tiny ellipses that might be chairs or dots
                        geom = cell.find('mxGeometry')
                        if geom is not None:
                            w = float(geom.get('width', 0))
                            h = float(geom.get('height', 0))
                            if w > 40 and h > 40: # Arbitrary threshold for "Table" vs "Chair"
                                result["round_table_count"] += 1
                                # Check for VIP styling (gold/yellow)
                                if 'fillcolor=#ffd700' in style or 'fillcolor=yellow' in style or 'fillcolor=#ffff00' in style or 'fillcolor=gold' in style:
                                    result["vip_highlight_count"] += 1
                            elif w > 0 and w <= 40:
                                # Likely a chair if small ellipse
                                result["chair_count"] += 1

                    # Identify Rectangular Tables / Stage / Bar
                    # Note: Default shape is often rect if not specified, but usually explicit in style
                    if 'rounded=0' in style or 'shape=rectangle' in style or 'rect' in style or 'whiteSpace=wrap' in style:
                        # Check labels to distinguish
                        if 'stage' in value:
                            result["has_stage"] = True
                        elif 'bar' in value:
                            result["has_bar"] = True
                        elif 'head' in value or 'speaker' in value:
                            result["rect_table_count"] += 1
                        else:
                            # Heuristic: Check size for standard chairs (often squares)
                            geom = cell.find('mxGeometry')
                            if geom is not None:
                                w = float(geom.get('width', 0))
                                if w > 0 and w < 40:
                                    result["chair_count"] += 1
                    
                    # Check for chair shapes specifically (some templates use specific shapes)
                    if 'chair' in style or 'seat' in style:
                        result["chair_count"] += 1
                        
                    # Collect numeric labels (1-6)
                    # Often label is just the value
                    if value.strip() in ['1', '2', '3', '4', '5', '6']:
                        result["labels_found"].append(value.strip())

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Merge results into final JSON
python3 << PYEOF
import json
import os

final = {
    "file_exists": "$FILE_EXISTS" == "true",
    "file_modified": "$FILE_MODIFIED" == "true",
    "png_exists": "$PNG_EXISTS" == "true",
    "png_size": int("$PNG_SIZE"),
    "analysis": {}
}

if os.path.exists("/tmp/gala_analysis.json"):
    with open("/tmp/gala_analysis.json") as f:
        final["analysis"] = json.load(f)

with open("$RESULT_JSON", "w") as f:
    json.dump(final, f, indent=2)
PYEOF

# Set permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true
echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"