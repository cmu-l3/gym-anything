#!/bin/bash
set -e

echo "=== Exporting Task Results ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence
PDF_PATH="/home/ga/Diagrams/3rd_floor_evacuation.pdf"
DIAGRAM_PATH="/home/ga/Diagrams/3rd_floor_plan.drawio"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PDF_EXISTS="false"
PDF_SIZE=0
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
fi

# 3. Analyze Diagram Content using Python
# We parse the XML to count shapes, find labels, and check colors
# This avoids relying solely on screenshots or timestamps
python3 << 'PYEOF'
import sys
import json
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import os
import re

diagram_path = "/home/ga/Diagrams/3rd_floor_plan.drawio"
pdf_path = "/home/ga/Diagrams/3rd_floor_evacuation.pdf"
start_time = int(open("/tmp/task_start_time.txt").read().strip())

result = {
    "file_exists": False,
    "file_modified": False,
    "pdf_exists": False,
    "total_shapes": 0,
    "total_edges": 0,
    "text_content": [],
    "colors_used": [],
    "has_legend": False,
    "has_title": False
}

if os.path.exists(pdf_path):
    result["pdf_exists"] = True

if os.path.exists(diagram_path):
    result["file_exists"] = True
    mtime = os.path.getmtime(diagram_path)
    if mtime > start_time:
        result["file_modified"] = True

    try:
        tree = ET.parse(diagram_path)
        root = tree.getroot()
        
        # Handle compressed draw.io files
        xml_content = None
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            try:
                # Decode: Base64 -> Inflate -> URLDecode
                # Note: draw.io usually does Deflate (zlib -15)
                data = base64.b64decode(diagram_node.text)
                xml_content = zlib.decompress(data, -15).decode('utf-8')
                xml_content = urllib.parse.unquote(xml_content)
                root = ET.fromstring(xml_content)
            except Exception as e:
                # Fallback: maybe it's just plain XML inside
                pass

        shapes = []
        edges = []
        texts = []
        styles = []

        for cell in root.findall(".//mxCell"):
            val = cell.get("value", "")
            style = cell.get("style", "")
            vertex = cell.get("vertex")
            edge = cell.get("edge")

            if vertex == "1":
                shapes.append(cell)
            if edge == "1":
                edges.append(cell)
            
            # Extract text (strip HTML)
            if val:
                clean_text = re.sub('<[^<]+?>', '', val).strip()
                if clean_text:
                    texts.append(clean_text)
            
            # Extract colors from style
            # Look for fillColor=#XXXXXX, strokeColor=#XXXXXX, or standard color names
            colors = re.findall(r'(?:fill|stroke)Color=([^;]+)', style)
            styles.extend(colors)

        result["total_shapes"] = len(shapes)
        result["total_edges"] = len(edges)
        result["text_content"] = texts
        result["colors_used"] = list(set(styles))
        
        # Heuristic checks
        full_text = " ".join(texts).lower()
        result["has_legend"] = "legend" in full_text or "key" in full_text
        result["has_title"] = "evacuation plan" in full_text or "building c" in full_text

    except Exception as e:
        result["error"] = str(e)

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# 4. Final Permissions Check
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="