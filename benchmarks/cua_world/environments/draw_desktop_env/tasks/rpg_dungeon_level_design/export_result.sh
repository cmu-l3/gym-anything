#!/bin/bash
# export_result.sh for rpg_dungeon_level_design
set -u

echo "=== Exporting RPG Dungeon Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/sunken_crypt.drawio"
PNG_FILE="/home/ga/Desktop/sunken_crypt.png"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence and Timestamps
DRAWIO_EXISTS=false
PNG_EXISTS=false
DRAWIO_MODIFIED_DURING_TASK=false
PNG_MODIFIED_DURING_TASK=false

if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS=true
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DRAWIO_MODIFIED_DURING_TASK=true
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS=true
    MTIME=$(stat -c %Y "$PNG_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PNG_MODIFIED_DURING_TASK=true
    fi
fi

# 3. Analyze draw.io XML content (Python)
# We handle both uncompressed XML and the compressed (deflate+base64) format draw.io uses.
python3 << 'PYEOF' > /tmp/drawio_analysis.json
import sys
import zlib
import base64
import json
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/sunken_crypt.drawio"
result = {
    "is_valid_xml": False,
    "text_labels": [],
    "room_count": 0,
    "edge_count": 0,
    "keywords_found": {}
}

REQUIRED_KEYWORDS = ["entry", "hall", "armory", "shrine", "treasure", "vault", "boss", "key", "trap", "loot", "start", "locked"]

def decode_diagram_data(raw_data):
    # draw.io creates a <diagram> tag containing text.
    # It might be raw XML (rare), or Base64 encoded Deflate stream.
    try:
        # Attempt 1: Base64 -> Deflate
        decoded = base64.b64decode(raw_data)
        # -15 for raw deflate (no header)
        decompressed = zlib.decompress(decoded, -15)
        return unquote(decompressed.decode('utf-8'))
    except Exception:
        # Attempt 2: Just URL decoding
        try:
            return unquote(raw_data)
        except:
            return raw_data

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        result["is_valid_xml"] = True
        
        # The XML might be stored in <diagram> tags
        diagrams = root.findall('diagram')
        
        full_xml_content = ""
        
        # Process each page (diagram)
        for diagram in diagrams:
            if diagram.text:
                page_xml = decode_diagram_data(diagram.text)
                full_xml_content += page_xml
        
        # If no <diagram> tags or empty, maybe it's an uncompressed file
        if not full_xml_content:
            with open(filepath, 'r') as f:
                full_xml_content = f.read()

        # Parse the inner XML content (which contains the actual graph model)
        # We need to wrap it to be valid XML if we extracted fragments, but simple string search is often enough for text
        # Let's try to extract labels using regex to be robust against XML structure variations
        
        # 1. Extract "value" attributes (labels)
        # <mxCell value="Entry Hall" ... />
        labels = re.findall(r'value="([^"]*)"', full_xml_content)
        
        # 2. Extract edge counts
        # <mxCell ... edge="1" ... />
        edges = re.findall(r'edge="1"', full_xml_content)
        result["edge_count"] = len(edges)
        
        clean_labels = []
        for l in labels:
            # Remove HTML tags if present (draw.io often wraps text in <div>)
            clean = re.sub(r'<[^>]+>', ' ', l).strip()
            if clean:
                clean_labels.append(clean)
        
        result["text_labels"] = clean_labels
        result["room_count"] = len(labels) # Rough proxy, refinement in verifier
        
        # Check for keywords
        lower_content = " ".join(clean_labels).lower()
        for kw in REQUIRED_KEYWORDS:
            result["keywords_found"][kw] = (kw in lower_content)
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Construct Final Result JSON
# Merge the shell variables and the python analysis
cat << EOF > /tmp/task_result.json
{
    "drawio_exists": $DRAWIO_EXISTS,
    "png_exists": $PNG_EXISTS,
    "drawio_modified": $DRAWIO_MODIFIED_DURING_TASK,
    "png_modified": $PNG_MODIFIED_DURING_TASK,
    "analysis": $(cat /tmp/drawio_analysis.json),
    "task_start_time": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"