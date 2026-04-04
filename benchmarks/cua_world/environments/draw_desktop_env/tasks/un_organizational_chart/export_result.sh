#!/bin/bash
echo "=== Exporting UN Org Chart task results ==="

DRAWIO_FILE="/home/ga/Desktop/un_org_chart.drawio"
PNG_FILE="/home/ga/Desktop/un_org_chart.png"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to parse drawio XML (handles compression) and generate result JSON
python3 << 'PYEOF' > "$RESULT_FILE" 2>/dev/null
import json
import os
import sys
import re
import base64
import zlib
import xml.etree.ElementTree as ET

drawio_file = "/home/ga/Desktop/un_org_chart.drawio"
png_file = "/home/ga/Desktop/un_org_chart.png"
task_start_str = os.popen('cat /tmp/task_start_time.txt 2>/dev/null').read().strip()
task_start = int(task_start_str) if task_start_str.isdigit() else 0

result = {
    "drawio_file_exists": False,
    "drawio_file_modified_after_start": False,
    "drawio_file_size": 0,
    "png_file_exists": False,
    "png_file_size": 0,
    "page_count": 0,
    "shape_count": 0,
    "edge_count": 0,
    "fill_colors": [],
    "principal_organs_found": [],
    "subsidiary_bodies_found": [],
    "specialized_agencies_found": []
}

def decompress_diagram(content):
    if not content: return None
    try:
        decoded = base64.b64decode(content)
        return zlib.decompress(decoded, -15)
    except:
        return None

if os.path.exists(drawio_file):
    stats = os.stat(drawio_file)
    result["drawio_file_exists"] = True
    result["drawio_file_size"] = stats.st_size
    result["drawio_file_modified_after_start"] = stats.st_mtime > task_start

    try:
        tree = ET.parse(drawio_file)
        root = tree.getroot()
        
        # Count pages
        diagrams = root.findall('diagram')
        result["page_count"] = len(diagrams)
        
        # Parse content
        all_text = []
        colors = set()
        
        for diagram in diagrams:
            content = diagram.text
            if content:
                # Handle compressed content
                xml_content = decompress_diagram(content)
                if xml_content:
                    try:
                        page_root = ET.fromstring(xml_content)
                        cells = list(page_root.iter('mxCell'))
                    except:
                        cells = []
                else:
                    # Maybe uncompressed
                    cells = []
            else:
                # Direct uncompressed XML
                cells = list(diagram.iter('mxCell'))
                
            # If cells were not found inside diagram tag, check root level
            if not cells:
                 cells = list(root.iter('mxCell'))

            for cell in cells:
                val = str(cell.get('value', '')).lower()
                style = str(cell.get('style', ''))
                
                # Check vertex (shapes)
                if cell.get('vertex') == '1':
                    result["shape_count"] += 1
                    # Extract text content (stripping HTML)
                    clean_text = re.sub(r'<[^>]+>', ' ', val).strip()
                    if clean_text:
                        all_text.append(clean_text)
                    
                    # Extract fill color
                    color_match = re.search(r'fillColor=([^;]+)', style)
                    if color_match:
                        c = color_match.group(1).lower()
                        if c not in ['none', 'default', '#ffffff', 'white']:
                            colors.add(c)
                            
                # Check edges
                elif cell.get('edge') == '1':
                    result["edge_count"] += 1

        result["fill_colors"] = list(colors)
        full_text_blob = " ".join(all_text)
        
        # Check Principal Organs
        organs = ["General Assembly", "Security Council", "Economic and Social Council", "ECOSOC", "International Court of Justice", "ICJ", "Secretariat", "Trusteeship Council"]
        result["principal_organs_found"] = [o for o in organs if o.lower() in full_text_blob]
        
        # Check Subsidiary Bodies
        bodies = ["UNHCR", "UNICEF", "UNDP", "UNEP", "WFP", "Human Rights Council", "UN Women", "UNCTAD", "Peacekeeping", "Sanctions", "Counter-Terrorism", "Criminal Tribunals", "Commission on the Status of Women", "Regional Commissions", "DPPA", "DPO", "OCHA", "DESA"]
        result["subsidiary_bodies_found"] = [b for b in bodies if b.lower() in full_text_blob]
        
        # Check Specialized Agencies
        agencies = ["WHO", "UNESCO", "FAO", "ILO", "IMF", "World Bank", "ICAO", "WMO", "WIPO", "ITU", "UNIDO", "IFAD", "UNWTO", "UPU", "IMO"]
        result["specialized_agencies_found"] = [a for a in agencies if a.lower() in full_text_blob]

    except Exception as e:
        print(f"Error parsing XML: {e}", file=sys.stderr)

if os.path.exists(png_file):
    result["png_file_exists"] = True
    result["png_file_size"] = os.path.getsize(png_file)

print(json.dumps(result, indent=2))
PYEOF

# Move to safe permission
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
cat "$RESULT_FILE"