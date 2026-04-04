#!/bin/bash
set -e

echo "=== Exporting Hospital DFD Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Analyze the .drawio file
# This is necessary because draw.io files are complex XML (sometimes compressed)
# We need to extract page counts, text labels, and structure.

cat << 'EOF' > /tmp/analyze_drawio.py
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import json
import os
import re

def decode_diagram_data(encoded_data):
    """Decode the typical draw.io compressed data."""
    try:
        # It's usually URL encoded, then Base64, then Deflate
        decoded = base64.b64decode(urllib.parse.unquote(encoded_data))
        # -15 for raw deflate (no header)
        xml_data = zlib.decompress(decoded, -15).decode('utf-8')
        return xml_data
    except Exception as e:
        # Fallback: maybe it's not compressed or different format
        return None

def parse_drawio(file_path):
    if not os.path.exists(file_path):
        return {"error": "File not found"}

    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except ET.ParseError:
        return {"error": "Invalid XML"}

    result = {
        "pages": [],
        "total_pages": 0,
        "total_shapes": 0,
        "total_edges": 0
    }

    # draw.io files can have multiple <diagram> tags (one per page)
    diagrams = root.findall('diagram')
    result["total_pages"] = len(diagrams)

    for diag in diagrams:
        page_name = diag.get('name', 'Untitled')
        page_data = {
            "name": page_name,
            "shapes": [],
            "edges": [],
            "labels": []
        }
        
        # content might be in the text of the tag (compressed) or children (uncompressed)
        xml_content = None
        if diag.text and diag.text.strip():
            xml_content = decode_diagram_data(diag.text)
        
        if xml_content:
            try:
                page_root = ET.fromstring(xml_content)
                cells = page_root.findall(".//mxCell")
            except:
                cells = []
        else:
            # Try finding mxGraphModel directly
            cells = diag.findall(".//mxCell")

        for cell in cells:
            # Check if it's a vertex (shape) or edge (connector)
            is_vertex = cell.get('vertex') == '1'
            is_edge = cell.get('edge') == '1'
            value = cell.get('value', '')
            
            # Clean HTML tags from label
            clean_label = re.sub('<[^<]+?>', '', value).strip()
            
            if is_vertex:
                page_data["shapes"].append(clean_label)
                if clean_label:
                    page_data["labels"].append(clean_label)
            elif is_edge:
                page_data["edges"].append(clean_label)
                if clean_label:
                    page_data["labels"].append(clean_label)

        result["total_shapes"] += len(page_data["shapes"])
        result["total_edges"] += len(page_data["edges"])
        result["pages"].append(page_data)

    return result

def check_file_timestamps(file_path, start_time):
    if not os.path.exists(file_path):
        return False
    mtime = os.path.getmtime(file_path)
    return mtime > start_time

# Run analysis
file_path = "/home/ga/Diagrams/hospital_dfd.drawio"
svg_path = "/home/ga/Diagrams/exports/hospital_dfd.svg"
start_time_path = "/tmp/task_start_time.txt"

analysis = parse_drawio(file_path)

# Add timestamp checks
start_time = 0
if os.path.exists(start_time_path):
    with open(start_time_path, 'r') as f:
        start_time = float(f.read().strip())

analysis["file_modified"] = check_file_timestamps(file_path, start_time)
analysis["svg_exists"] = os.path.exists(svg_path)
if analysis["svg_exists"]:
    analysis["svg_modified"] = check_file_timestamps(svg_path, start_time)
    analysis["svg_size"] = os.path.getsize(svg_path)

print(json.dumps(analysis, indent=2))
EOF

# Run the python script and save output
python3 /tmp/analyze_drawio.py > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Analysis complete. JSON result generated."
cat /tmp/task_result.json