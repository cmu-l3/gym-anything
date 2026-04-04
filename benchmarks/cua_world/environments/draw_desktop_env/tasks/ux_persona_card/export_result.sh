#!/bin/bash
# export_result.sh for ux_persona_card

echo "=== Exporting Task Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Python Script to Analyze the .drawio file (XML)
# We need to handle draw.io's XML structure which can be compressed or uncompressed.
# We also check for the PNG export.

python3 << 'PY_EOF' > /tmp/task_result.json
import json
import os
import re
import zlib
import base64
import sys
import xml.etree.ElementTree as ET
from urllib.parse import unquote

DRAWIO_PATH = "/home/ga/Desktop/persona_card.drawio"
PNG_PATH = "/home/ga/Desktop/persona_card.png"

result = {
    "drawio_exists": False,
    "png_exists": False,
    "png_valid": False,
    "image_embedded": False,
    "text_content_found": [],
    "slider_widgets_count": 0,
    "grouping_used": False,
    "file_timestamp_valid": False
}

def decode_diagram(root):
    """Decode compressed draw.io XML data if present."""
    # Check for mxfile/diagram/mxGraphModel structure (uncompressed)
    if root.find(".//mxGraphModel") is not None:
        return root

    # Check for mxfile/diagram (compressed)
    diagram_node = root.find("diagram")
    if diagram_node is not None and diagram_node.text:
        try:
            # Base64 decode
            data = base64.b64decode(diagram_node.text)
            # Inflate (raw deflate)
            xml_str = zlib.decompress(data, -15).decode('utf-8')
            # URL decode if needed
            xml_str = unquote(xml_str)
            return ET.fromstring(f"<root>{xml_str}</root>")
        except Exception as e:
            pass
    return root

# --- Check Files ---
if os.path.exists(DRAWIO_PATH):
    result["drawio_exists"] = True
    # Check timestamp
    if os.path.getmtime(DRAWIO_PATH) > float(os.environ.get('TASK_START', 0)):
        result["file_timestamp_valid"] = True

    try:
        tree = ET.parse(DRAWIO_PATH)
        root = decode_diagram(tree.getroot())

        # 1. Check for Image Embedding
        # Look for style="...image=..." or <image> tags
        xml_str = ET.tostring(root, encoding='unicode')
        if 'image=' in xml_str or 'image;' in xml_str or '<image' in xml_str:
            result["image_embedded"] = True
        
        # 2. Check Text Content
        # We look for specific keywords from the persona
        keywords = ["Penny", "Parker", "Project Manager", "Introvert", "Extrovert", "Goals", "Frustrations"]
        lower_xml = xml_str.lower()
        for kw in keywords:
            if kw.lower() in lower_xml:
                result["text_content_found"].append(kw)

        # 3. Check for Slider Widgets (Lines + Circles)
        # Lines usually have `edge="1"` or `shape=line`
        # Circles usually have `shape=ellipse`
        # We want to see pairs of these.
        
        lines = 0
        circles = 0
        
        for mxcell in root.iter("mxCell"):
            style = mxcell.get("style", "").lower()
            
            # Count ellipses (circles)
            if "ellipse" in style:
                circles += 1
            
            # Count lines (either explicit line shape or an edge)
            # A visual slider line is often a static line shape, not necessarily a connector
            if "line" in style or "endarrow=none" in style:
                lines += 1
            # Edges can also count if used as lines
            if mxcell.get("edge") == "1":
                # Ensure it's a straight line (visual slider track)
                lines += 1

        # We need roughly 3 sets. 
        # Logic: If we have at least 3 circles and at least 3 line-like elements, we credit the sliders.
        if circles >= 3 and lines >= 3:
            result["slider_widgets_count"] = min(circles, lines)

        # 4. Check for Grouping
        # Grouping usually involves a cell that is a parent to others, often style="group" 
        # or just a container vertex.
        has_group = False
        for mxcell in root.iter("mxCell"):
            style = mxcell.get("style", "").lower()
            if "group" in style or "container" in style:
                has_group = True
                break
        
        # Alternative check: parent structure
        # If multiple cells point to the same parent (other than default layer '1'), it's grouped
        parents = [c.get("parent") for c in root.iter("mxCell") if c.get("parent") not in [None, "0", "1"]]
        if len(parents) > 5: # Arbitrary threshold: if many items are nested, grouping was used
             has_group = True
             
        result["grouping_used"] = has_group

    except Exception as e:
        result["xml_error"] = str(e)

if os.path.exists(PNG_PATH):
    result["png_exists"] = True
    if os.path.getsize(PNG_PATH) > 1000: # Empty images are usually tiny
        result["png_valid"] = True

print(json.dumps(result))
PY_EOF

# Set permissions for verifier to read
chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="