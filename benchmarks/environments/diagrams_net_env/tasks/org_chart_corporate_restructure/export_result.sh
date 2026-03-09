#!/bin/bash
echo "=== Exporting Org Chart Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Source files
DIAGRAM_PATH="/home/ga/Diagrams/org_chart.drawio"
EXPORT_PNG="/home/ga/Diagrams/exports/org_chart.png"
EXPORT_PDF="/home/ga/Diagrams/exports/org_chart.pdf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Analyze diagram file using Python script within the container
# This is necessary because the file might be compressed XML, which bash handles poorly
# We output a JSON structure that the Verifier (on host) will read.

python3 << 'PYEOF'
import sys
import os
import json
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import re

diagram_path = "/home/ga/Diagrams/org_chart.drawio"
task_start = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0
png_path = "/home/ga/Diagrams/exports/org_chart.png"
pdf_path = "/home/ga/Diagrams/exports/org_chart.pdf"

result = {
    "file_exists": False,
    "file_modified": False,
    "png_exists": False,
    "png_size": 0,
    "pdf_exists": False,
    "pdf_size": 0,
    "node_count": 0,
    "edge_count": 0,
    "all_text": "",
    "styles_found": [],
    "distinct_colors": 0,
    "labels_found": []
}

def decode_drawio_content(encoded_text):
    """Decode draw.io compressed diagram content."""
    try:
        # Standard draw.io compression: URL decode -> Base64 decode -> Inflate (no header)
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded)
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception:
        # Sometimes it might just be XML
        return encoded_text

if os.path.exists(diagram_path):
    result["file_exists"] = True
    mtime = os.path.getmtime(diagram_path)
    if mtime > task_start:
        result["file_modified"] = True
    
    try:
        tree = ET.parse(diagram_path)
        root = tree.getroot()
        
        # Parse Diagram Content
        # draw.io files can be plain XML or contain compressed <diagram> nodes
        all_cells = []
        
        if root.tag == 'mxfile':
            for diagram in root.findall('diagram'):
                if diagram.text and diagram.text.strip():
                    xml_content = decode_drawio_content(diagram.text)
                    if xml_content.startswith('<'):
                        try:
                            diag_tree = ET.fromstring(xml_content)
                            all_cells.extend(diag_tree.findall('.//mxCell'))
                        except:
                            pass
                else:
                    # Uncompressed inside diagram node
                    all_cells.extend(diagram.findall('.//mxCell'))
        else:
            # Fallback for plain mxGraphModel
            all_cells.extend(root.findall('.//mxCell'))
            
        # Analyze Cells
        colors = set()
        
        for cell in all_cells:
            # Get attributes
            value = cell.get('value', '')
            style = cell.get('style', '')
            vertex = cell.get('vertex')
            edge = cell.get('edge')
            
            # Count Nodes/Edges
            if vertex == '1':
                # Filter out container/root nodes which usually have no parent or specific IDs
                parent = cell.get('parent')
                if parent and parent != '0':
                    result["node_count"] += 1
                    
                    # Clean text (remove HTML tags if any)
                    clean_text = re.sub('<[^<]+?>', ' ', value).replace('&nbsp;', ' ')
                    clean_text = " ".join(clean_text.split())
                    if clean_text:
                        result["all_text"] += clean_text + " | "
                        result["labels_found"].append(clean_text)
                    
                    # Extract Colors
                    # Look for fillColor=#XXXXXX
                    color_match = re.search(r'fillColor=(#[0-9A-Fa-f]{6}|[a-z]+)', style)
                    if color_match:
                        color = color_match.group(1).lower()
                        if color != 'none' and color != 'white' and color != '#ffffff':
                            colors.add(color)
                        
            if edge == '1':
                result["edge_count"] += 1
        
        result["distinct_colors"] = len(colors)
        result["styles_found"] = list(colors)

    except Exception as e:
        result["error"] = str(e)

# Check Exports
if os.path.exists(png_path):
    result["png_exists"] = True
    result["png_size"] = os.path.getsize(png_path)

if os.path.exists(pdf_path):
    result["pdf_exists"] = True
    result["pdf_size"] = os.path.getsize(pdf_path)

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Analysis complete. Result saved to /tmp/task_result.json"