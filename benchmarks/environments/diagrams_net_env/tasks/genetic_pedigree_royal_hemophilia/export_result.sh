#!/bin/bash
echo "=== Exporting Genetic Pedigree Result ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to analyze the .drawio XML content
# This handles extraction of shapes, text, styles, and counts
python3 << 'PYEOF'
import sys
import os
import json
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import re
import time

# Paths
DRAWIO_PATH = "/home/ga/Diagrams/royal_hemophilia_pedigree.drawio"
PDF_PATH = "/home/ga/Diagrams/royal_hemophilia_pedigree.pdf"
TASK_START_FILE = "/tmp/task_start_time.txt"

result = {
    "file_exists": False,
    "pdf_exists": False,
    "file_modified_during_task": False,
    "shapes_total": 0,
    "males": 0,
    "females": 0,
    "affected": 0,
    "carriers": 0,
    "connections": 0,
    "text_content": [],
    "generations_found": [],
    "legend_found": False
}

def decode_drawio(content):
    """Decode diagram data if compressed."""
    try:
        # Check if it's a raw XML file first
        if content.strip().startswith('<mxfile') and 'compressed="false"' in content:
            return content
        
        # Parse XML to find diagram tag
        root = ET.fromstring(content)
        diagram = root.find('diagram')
        if diagram is None or not diagram.text:
            # Maybe it's uncompressed inside diagram tag?
            return content
            
        # Decode: Base64 -> Inflate (no header) -> UrlDecode
        # draw.io usually does: raw -> deflate -> base64
        data = base64.b64decode(diagram.text)
        try:
            xml_str = zlib.decompress(data, -15).decode('utf-8')
            # URL decode
            xml_str = urllib.parse.unquote(xml_str)
            return f"<root>{xml_str}</root>" # Wrap to make valid XML for parsing parts
        except Exception as e:
            # Fallback for other compressions
            return content
    except Exception as e:
        print(f"Error decoding: {e}")
        return content

if os.path.exists(DRAWIO_PATH):
    result["file_exists"] = True
    
    # Check timestamps
    try:
        file_mtime = os.path.getmtime(DRAWIO_PATH)
        if os.path.exists(TASK_START_FILE):
            with open(TASK_START_FILE, 'r') as f:
                start_time = float(f.read().strip())
            if file_mtime > start_time:
                result["file_modified_during_task"] = True
    except Exception:
        pass

    # Parse content
    try:
        with open(DRAWIO_PATH, 'r') as f:
            raw_content = f.read()
        
        xml_content = decode_drawio(raw_content)
        
        # Robust parsing even if partial
        # We look for mxCell elements
        root = ET.fromstring(xml_content) if not xml_content.startswith('<root>') else ET.fromstring(xml_content)
        
        all_cells = root.findall(".//mxCell")
        
        for cell in all_cells:
            style = str(cell.get('style', '')).lower()
            value = str(cell.get('value', ''))
            vertex = cell.get('vertex')
            edge = cell.get('edge')
            
            # Text Content
            # Strip HTML tags from labels
            clean_text = re.sub('<[^<]+?>', '', value).strip()
            if clean_text:
                result["text_content"].append(clean_text)
                
            # Generations
            if clean_text in ["I", "II", "III", "IV"]:
                if clean_text not in result["generations_found"]:
                    result["generations_found"].append(clean_text)
            
            # Legend detection
            if "legend" in clean_text.lower() or "key" in clean_text.lower():
                result["legend_found"] = True

            # Shape Classification
            if vertex == "1":
                result["shapes_total"] += 1
                
                # Gender (Shape based)
                if "ellipse" in style:
                    result["females"] += 1
                elif "whiteSpace=wrap" in style and "ellipse" not in style:
                    # Default rectangles usually have whiteSpace=wrap
                    result["males"] += 1
                
                # Status (Fill based)
                # Affected often black (#000000) or dark
                if "fillcolor=#000000" in style or "fillcolor=#333333" in style:
                    result["affected"] += 1
                
                # Carrier logic implies distinct style (not white, not black)
                # Or specific dot symbols. Hard to detect perfectly, but can check for visual distinction.
                # Assuming agent uses a specific fill or overlay.
                # If they use a group (circle + dot), it counts as multiple shapes.
                # We'll check text labels for "carrier" as fallback or specific graphics.
                pass 

            if edge == "1":
                result["connections"] += 1
                
    except Exception as e:
        print(f"Parsing Error: {e}")

if os.path.exists(PDF_PATH):
    result["pdf_exists"] = True
    # Simple check for valid PDF header
    with open(PDF_PATH, 'rb') as f:
        header = f.read(4)
        if header == b'%PDF':
            pass # Valid header

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

print("Analysis complete.")
PYEOF

# 3. Permissions fix
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json