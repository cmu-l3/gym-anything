#!/bin/bash
# export_result.sh for mastodon_c4_model

echo "=== Exporting Mastodon C4 Task Results ==="

# 1. Capture final state visual
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamps
DRAWIO_FILE="/home/ga/Desktop/mastodon_c4.drawio"
PNG_FILE="/home/ga/Desktop/mastodon_c4.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
PNG_EXISTS="false"
FILE_MODIFIED="false"
PNG_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# 3. Analyze the draw.io XML content using Python
# This handles compressed XML diagrams and extracts text/structure
python3 << 'PYEOF' > /tmp/drawio_analysis.json 2>/dev/null
import sys
import os
import zlib
import base64
import json
import xml.etree.ElementTree as ET
from urllib.parse import unquote

file_path = "/home/ga/Desktop/mastodon_c4.drawio"

result = {
    "error": None,
    "page_count": 0,
    "total_shapes": 0,
    "total_edges": 0,
    "text_content": [],  # List of strings found in labels
    "boundaries_found": 0,
    "pages_data": [] # {name: str, shapes: int, edges: int, text: []}
}

def decode_diagram_data(text):
    if not text: return ""
    try:
        # Try standard base64 + inflate
        decoded = base64.b64decode(text)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except:
        try:
            # Try URL decode
            return unquote(text)
        except:
            return ""

if not os.path.exists(file_path):
    result["error"] = "File not found"
    print(json.dumps(result))
    sys.exit(0)

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    diagrams = root.findall('diagram')
    result["page_count"] = len(diagrams)

    for diag in diagrams:
        page_info = {"name": diag.get("name", "Unknown"), "shapes": 0, "edges": 0, "text": []}
        
        # Get content
        content = diag.text
        xml_content = decode_diagram_data(content)
        
        if not xml_content:
            # Maybe it's not compressed?
            if len(list(diag)) > 0:
                # Iterate mxGraphModel directly if present
                cells = diag.findall(".//mxCell")
            else:
                cells = []
        else:
            try:
                mx_root = ET.fromstring(xml_content)
                cells = mx_root.findall(".//mxCell")
            except:
                cells = []

        for cell in cells:
            style = cell.get("style", "")
            value = cell.get("value", "")
            is_edge = cell.get("edge") == "1"
            is_vertex = cell.get("vertex") == "1"
            
            # Clean HTML from value
            clean_value = ""
            if value:
                # Rudimentary HTML strip
                clean_value = ''.join(xml.etree.ElementTree.fromstring(f"<r>{value}</r>").itertext())
            
            if is_vertex:
                page_info["shapes"] += 1
                result["total_shapes"] += 1
                if "group" in style or "swimlane" in style or "container" in style:
                    result["boundaries_found"] += 1
            
            if is_edge:
                page_info["edges"] += 1
                result["total_edges"] += 1

            if clean_value.strip():
                page_info["text"].append(clean_value.lower())
                result["text_content"].append(clean_value.lower())
        
        result["pages_data"].append(page_info)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Construct Final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/drawio_analysis.json)
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json