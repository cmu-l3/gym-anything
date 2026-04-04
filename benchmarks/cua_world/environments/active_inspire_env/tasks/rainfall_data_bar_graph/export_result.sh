#!/bin/bash
echo "=== Exporting rainfall_data_bar_graph task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
FILE_PATH="/home/ga/Documents/Flipcharts/rainfall_graph.flipchart"
FILE_PATH_ALT="/home/ga/Documents/Flipcharts/rainfall_graph.flp"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Determine actual file path
ACTUAL_PATH=""
if [ -f "$FILE_PATH" ]; then
    ACTUAL_PATH="$FILE_PATH"
elif [ -f "$FILE_PATH_ALT" ]; then
    ACTUAL_PATH="$FILE_PATH_ALT"
fi

# Basic file stats
FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
CREATED_DURING_TASK="false"

if [ -n "$ACTUAL_PATH" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(get_file_size "$ACTUAL_PATH")
    FILE_MTIME=$(get_file_mtime "$ACTUAL_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Use Python to parse the flipchart XML specifically for geometry
# This script extracts text content and shape dimensions (x, y, width, height)
python3 -c '
import sys
import zipfile
import json
import os
import re
import xml.etree.ElementTree as ET

file_path = "'"$ACTUAL_PATH"'"
result = {
    "text_content": [],
    "shapes": [],
    "error": None
}

if not os.path.exists(file_path):
    result["error"] = "File not found"
    print(json.dumps(result))
    sys.exit(0)

try:
    with zipfile.ZipFile(file_path, "r") as z:
        # Find page XML files
        xml_files = [f for f in z.namelist() if f.endswith(".xml")]
        
        for xml_file in xml_files:
            try:
                content = z.read(xml_file)
                root = ET.fromstring(content)
                
                # Extract Text
                # Text can be in various tags, look for text strings
                # ActivInspire often puts text in "text" attributes or CDATA
                # We simply recursively look for text-like attributes or content
                for elem in root.iter():
                    # Check common text attributes
                    for attr in ["text", "Text", "caption", "Caption"]:
                        if attr in elem.attrib:
                            result["text_content"].append(elem.attrib[attr])
                    
                    # Check element text content
                    if elem.text and len(elem.text.strip()) > 0:
                        result["text_content"].append(elem.text.strip())

                # Extract Shapes (Rectangles)
                # Looking for AsRectangle, RectangleShape, or AsShape with type="rectangle"
                for elem in root.iter():
                    tag_name = elem.tag.split("}")[-1] # strip namespace
                    
                    is_rect = False
                    if "Rectangle" in tag_name:
                        is_rect = True
                    elif "Shape" in tag_name and "Rectangle" in str(elem.attrib):
                        is_rect = True
                        
                    if is_rect:
                        # Try to find geometry attributes (often left, top, width, height)
                        # ActivInspire XML is inconsistent across versions, check likely keys
                        shape_data = {"tag": tag_name}
                        
                        # Geometry
                        for k in ["left", "x", "Left", "X"]:
                            if k in elem.attrib: shape_data["x"] = float(elem.attrib[k])
                        for k in ["top", "y", "Top", "Y"]:
                            if k in elem.attrib: shape_data["y"] = float(elem.attrib[k])
                        for k in ["width", "w", "Width", "W"]:
                            if k in elem.attrib: shape_data["width"] = float(elem.attrib[k])
                        for k in ["height", "h", "Height", "H"]:
                            if k in elem.attrib: shape_data["height"] = float(elem.attrib[k])
                            
                        # Color (fillColor, color)
                        for k in ["fillColor", "color", "Color", "FillColor"]:
                            if k in elem.attrib: shape_data["color"] = elem.attrib[k]
                            
                        # Only add if we got dimensions
                        if "width" in shape_data and "height" in shape_data:
                            result["shapes"].append(shape_data)

            except Exception as e:
                continue # Skip malformed XML files inside zip

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
' > /tmp/content_analysis.json

# Merge results
python3 -c '
import json
import os

try:
    with open("/tmp/content_analysis.json", "r") as f:
        content = json.load(f)
except:
    content = {"text_content": [], "shapes": []}

final_result = {
    "file_found": '$FILE_FOUND',
    "file_path": "'"$ACTUAL_PATH"'",
    "file_size": '$FILE_SIZE',
    "created_during_task": '$CREATED_DURING_TASK',
    "content": content,
    "timestamp": "'$(date -Iseconds)'"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(final_result, f)
'

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="