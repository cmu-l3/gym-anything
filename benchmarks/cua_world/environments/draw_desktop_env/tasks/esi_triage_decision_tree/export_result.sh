#!/bin/bash
# Do NOT use set -e to prevent early exit on safe failures

echo "=== Exporting ESI Triage Task Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/esi_triage_tree.drawio"
PNG_FILE="/home/ga/Desktop/esi_triage_tree.png"

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# 3. Deep Analysis of draw.io XML (Python)
# This script parses the .drawio XML to count shapes, pages, check colors, and extract text.
# It handles the common compressed XML format used by draw.io.

python3 << 'PYEOF' > /tmp/drawio_analysis.json 2>/dev/null || true
import sys, os, zlib, base64, json, re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

file_path = "/home/ga/Desktop/esi_triage_tree.drawio"
result = {
    "parsed": False,
    "page_count": 0,
    "shape_count": 0,
    "connector_count": 0,
    "decision_node_count": 0,
    "unique_fill_colors": [],
    "text_content": "",
    "keywords_found": []
}

if not os.path.exists(file_path):
    print(json.dumps(result))
    sys.exit(0)

def decode_diagram_data(data):
    """Decode raw XML, URL-encoded, or Deflate+Base64 compressed data."""
    try:
        # Attempt 1: Raw XML
        return ET.fromstring(data)
    except:
        pass
    
    try:
        # Attempt 2: URL Decoded
        return ET.fromstring(unquote(data))
    except:
        pass

    try:
        # Attempt 3: Base64 + Deflate (standard draw.io compressed)
        decoded = base64.b64decode(data)
        decompressed = zlib.decompress(decoded, -15) # -15 for raw deflate
        return ET.fromstring(decompressed)
    except:
        return None

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    result["parsed"] = True
    
    # Count pages
    diagrams = root.findall("diagram")
    result["page_count"] = len(diagrams)
    
    all_text = []
    
    # Process each page
    for diagram in diagrams:
        mxGraphModel = decode_diagram_data(diagram.text)
        if mxGraphModel is None:
            # Maybe uncompressed inside the diagram tag?
            mxGraphModel = diagram.find("mxGraphModel")
        
        if mxGraphModel is not None:
            root_cell = mxGraphModel.find("root")
            if root_cell is not None:
                for cell in root_cell.findall("mxCell"):
                    # Extract attributes
                    style = cell.get("style", "").lower()
                    value = cell.get("value", "")
                    
                    # Accumulate text (strip HTML)
                    clean_text = re.sub('<[^<]+?>', ' ', value).strip().lower()
                    if clean_text:
                        all_text.append(clean_text)
                    
                    # Classify Shapes
                    if cell.get("vertex") == "1":
                        result["shape_count"] += 1
                        
                        # Identify Decision Nodes (Diamond/Rhombus)
                        if "rhombus" in style or "diamond" in style or "?" in clean_text:
                            result["decision_node_count"] += 1
                            
                        # Extract Fill Colors
                        # Look for fillColor=#XXXXXX or fillColor=red
                        color_match = re.search(r'fillcolor=([^;]+)', style)
                        if color_match:
                            c = color_match.group(1)
                            if c not in ["none", "white", "#ffffff", "default"]:
                                if c not in result["unique_fill_colors"]:
                                    result["unique_fill_colors"].append(c)
                                    
                    elif cell.get("edge") == "1":
                        result["connector_count"] += 1

    result["text_content"] = " ".join(all_text)
    
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/drawio_analysis.json)
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json