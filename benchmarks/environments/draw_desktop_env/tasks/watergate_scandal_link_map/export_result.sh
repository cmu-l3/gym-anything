#!/bin/bash
echo "=== Exporting Watergate Map Results ==="

# Paths
DRAWIO_FILE="/home/ga/Desktop/watergate_map.drawio"
PNG_FILE="/home/ga/Desktop/watergate_map.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to analyze the draw.io XML structure
# This handles compressed XML (deflate) and parses entities/relationships
python3 << 'PY_EOF' > /tmp/xml_analysis.json
import sys
import os
import zlib
import base64
import json
import xml.etree.ElementTree as ET
from urllib.parse import unquote

file_path = "/home/ga/Desktop/watergate_map.drawio"
png_path = "/home/ga/Desktop/watergate_map.png"
task_start = int(sys.argv[1]) if len(sys.argv) > 1 else 0

result = {
    "drawio_exists": False,
    "png_exists": False,
    "file_fresh": False,
    "actors_found": [],
    "groups_found": [],
    "edge_count": 0,
    "labeled_edge_count": 0,
    "png_size": 0
}

# Check files
if os.path.exists(file_path):
    result["drawio_exists"] = True
    mtime = os.path.getmtime(file_path)
    if mtime > task_start:
        result["file_fresh"] = True

    try:
        # Parse XML (handle draw.io compression)
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Check if content is compressed in a diagram node
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            try:
                # Try standard base64 deflate
                decoded = base64.b64decode(diagram_node.text)
                xml_content = zlib.decompress(decoded, -15).decode('utf-8')
                root = ET.fromstring(f"<root>{xml_content}</root>") # Wrap to parse fragment
            except Exception:
                # Might be URL encoded or uncompressed
                try:
                    xml_content = unquote(diagram_node.text)
                    root = ET.fromstring(f"<root>{xml_content}</root>")
                except:
                    pass # Keep original root if decompression fails

        # Analyze Content
        actors_to_find = ["nixon", "haldeman", "mitchell", "liddy", "mccord", "dean", "hunt", "magruder", "ehrlichman"]
        groups_to_find = ["white house", "creep", "operative", "plumber"]
        
        # Helper to extract text from cell
        def get_text(cell):
            val = cell.get('value', '')
            # Simple HTML strip
            import re
            clean = re.sub('<[^<]+?>', ' ', val)
            return clean.lower()

        for cell in root.iter('mxCell'):
            text = get_text(cell)
            style = cell.get('style', '').lower()
            
            # Check for Edges
            if cell.get('edge') == '1':
                result["edge_count"] += 1
                if text.strip(): # Has label
                    result["labeled_edge_count"] += 1
            
            # Check for Vertices (Actors or Groups)
            elif cell.get('vertex') == '1':
                # Check for Actors
                for actor in actors_to_find:
                    if actor in text and actor not in result["actors_found"]:
                        result["actors_found"].append(actor)
                
                # Check for Groups
                # Look for group styles or container properties
                is_group_style = 'swimlane' in style or 'group' in style or 'container' in style
                # Or just large boxes with titles
                for group in groups_to_find:
                    if group in text and group not in result["groups_found"]:
                        result["groups_found"].append(group)

    except Exception as e:
        result["error"] = str(e)

if os.path.exists(png_path):
    result["png_exists"] = True
    result["png_size"] = os.path.getsize(png_path)

print(json.dumps(result))
PY_EOF
"$TASK_START"

# 3. Move result to final location safely
mv /tmp/xml_analysis.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json