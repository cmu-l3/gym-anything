#!/bin/bash
echo "=== Exporting AgTech Component Library Result ==="

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File Paths
LIB_PATH="/home/ga/Diagrams/SmartGrow_Lib.xml"
DIAGRAM_PATH="/home/ga/Diagrams/field_deployment.drawio"

# Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to analyze the XML content of both files
# Draw.io files are often Deflate+Base64 compressed. This script handles both raw XML and compressed.
python3 << 'PY_EOF'
import sys
import os
import zlib
import base64
import json
import urllib.parse
import xml.etree.ElementTree as ET
import re

lib_path = "/home/ga/Diagrams/SmartGrow_Lib.xml"
diag_path = "/home/ga/Diagrams/field_deployment.drawio"
result = {
    "lib_exists": False,
    "lib_models_count": 0,
    "diagram_exists": False,
    "diagram_shapes_count": 0,
    "diagram_groups_count": 0,
    "has_triangle": False,
    "has_ellipse": False,
    "has_green_fill": False,
    "has_brown_fill": False,
    "has_blue_fill": False,
    "has_red_fill": False,
    "hub_label_count": 0,
    "probe_label_count": 0,
    "edge_count": 0
}

def decode_drawio(content):
    """Decode draw.io content (URI encoded -> Base64 -> Inflate) or return raw if XML."""
    content = content.strip()
    if content.startswith('<'): 
        return content # Raw XML
    try:
        # Standard draw.io compression
        decoded = base64.b64decode(content)
        decompressed = zlib.decompress(decoded, -15)
        return decompressed.decode('utf-8')
    except:
        try:
            # URL encoded first?
            url_decoded = urllib.parse.unquote(content)
            decoded = base64.b64decode(url_decoded)
            decompressed = zlib.decompress(decoded, -15)
            return decompressed.decode('utf-8')
        except:
            return None

def analyze_xml(xml_string, is_library=False):
    info = {
        "models": 0,
        "groups": 0,
        "shapes": 0,
        "edges": 0,
        "styles": [],
        "labels": []
    }
    try:
        if is_library:
            # Libraries are wrapped in <mxLibrary> with JSON-like model array
            root = ET.fromstring(xml_string)
            if root.tag == 'mxlibrary':
                # The library content is often a JSON array of compressed XML strings
                content = root.text
                if content and '[' in content:
                    models = json.loads(content)
                    info["models"] = len(models)
            elif root.tag == 'mxGraphModel':
                 info["models"] = 1
        else:
            # Normal diagram
            root = ET.fromstring(xml_string)
            # Find all mxCell
            for cell in root.findall(".//mxCell"):
                style = cell.get("style", "")
                value = cell.get("value", "")
                parent = cell.get("parent", "")
                
                info["styles"].append(style)
                if value: info["labels"].append(value)
                
                # Check for Group: A vertex with children usually implies grouping structure,
                # but explicit groups often have style="group" or are parent to others
                # In draw.io XML, a group is usually a vertex=1 with children pointing to it.
                # Simplified check: if style contains "group"
                if "group" in style:
                    info["groups"] += 1
                
                if cell.get("vertex") == "1":
                    info["shapes"] += 1
                if cell.get("edge") == "1":
                    info["edges"] += 1

    except Exception as e:
        print(f"Error parsing XML: {e}", file=sys.stderr)
    return info

# 1. Analyze Library
if os.path.exists(lib_path):
    result["lib_exists"] = True
    try:
        with open(lib_path, 'r') as f:
            raw = f.read()
            # Libraries are weird. Sometimes just <mxlibrary>[JSON]</mxlibrary>
            res = analyze_xml(raw, is_library=True)
            result["lib_models_count"] = res["models"]
    except Exception as e:
        print(f"Lib read error: {e}", file=sys.stderr)

# 2. Analyze Diagram
if os.path.exists(diag_path):
    result["diagram_exists"] = True
    try:
        with open(diag_path, 'r') as f:
            raw = f.read()
        
        # Draw.io files have <mxfile><diagram>ENCODED_CONTENT</diagram></mxfile>
        try:
            tree = ET.fromstring(raw)
            # Iterate over diagrams (pages)
            full_style_list = []
            full_label_list = []
            
            for diagram in tree.findall("diagram"):
                txt = diagram.text
                if txt:
                    decoded_xml = decode_drawio(txt)
                    if decoded_xml:
                        # Now parse the actual graph model
                        analysis = analyze_xml(decoded_xml)
                        result["diagram_shapes_count"] += analysis["shapes"]
                        result["diagram_groups_count"] += analysis["groups"]
                        result["edge_count"] += analysis["edges"]
                        full_style_list.extend(analysis["styles"])
                        full_label_list.extend(analysis["labels"])
            
            # Check specific attributes in styles/labels
            styles_str = " ".join(full_style_list).lower()
            labels_str = " ".join(full_label_list).lower()
            
            if "triangle" in styles_str: result["has_triangle"] = True
            if "ellipse" in styles_str: result["has_ellipse"] = True
            
            # Hex codes (draw.io usually keeps case, but we lowered string)
            if "d5e8d4" in styles_str: result["has_green_fill"] = True
            if "a0522d" in styles_str: result["has_brown_fill"] = True
            if "dae8fc" in styles_str: result["has_blue_fill"] = True
            if "ff0000" in styles_str: result["has_red_fill"] = True
            
            result["hub_label_count"] = labels_str.count("hub")
            result["probe_label_count"] = labels_str.count("probe")
            
            # Additional heuristic for Groups: 
            # If we didn't find explicit "group" style (common in older versions), 
            # we rely on the user instructions which enforcing grouping.
            # Real grouping often results in nested cells.
            
        except ET.ParseError:
            # Maybe it's an uncompressed XML file directly?
            analysis = analyze_xml(raw)
            result["diagram_shapes_count"] = analysis["shapes"]
            # ... (repeat checks if needed, but standard save is compressed)

    except Exception as e:
        print(f"Diagram read error: {e}", file=sys.stderr)

# Output JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PY_EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json