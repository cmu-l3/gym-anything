#!/bin/bash
# export_result.sh for northwind_data_vault_architecture
# Parses draw.io XML to verify Data Vault compliance

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Desktop/northwind_dv.drawio"
PNG_FILE="/home/ga/Desktop/northwind_dv.png"

# 1. Basic File Checks
FILE_EXISTS="false"
PNG_EXISTS="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# 2. Advanced Analysis with Python
# We need to parse the XML to check for specific Data Vault structures.
# draw.io often compresses XML (deflate), so the python script handles that.

python3 << 'PYEOF' > /tmp/dv_analysis.json
import sys
import os
import zlib
import base64
import json
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

file_path = "/home/ga/Desktop/northwind_dv.drawio"

result = {
    "hubs_found": 0,
    "links_found": 0,
    "sats_found": 0,
    "hub_colors_correct": 0,
    "link_colors_correct": 0,
    "sat_colors_correct": 0,
    "metadata_columns_found": 0,
    "edges_count": 0,
    "labels": [],
    "error": None
}

def decode_diagram(root):
    # draw.io can store data in compressed format inside <diagram> tag
    diagram_node = root.find('diagram')
    if diagram_node is not None and diagram_node.text:
        try:
            # Try standard base64 + inflate
            data = base64.b64decode(diagram_node.text)
            xml_str = zlib.decompress(data, -15).decode('utf-8')
            return ET.fromstring(unquote(xml_str))
        except Exception:
            # Sometimes it's just raw XML inside or just URI encoded
            try:
                return ET.fromstring(unquote(diagram_node.text))
            except:
                pass
    return root

try:
    if os.path.exists(file_path):
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # If compressed, decode
        content_root = decode_diagram(root)
        
        # Analyze shapes (mxCells)
        for cell in content_root.iter('mxCell'):
            val = str(cell.get('value', '')).lower()
            style = str(cell.get('style', '')).lower()
            is_vertex = cell.get('vertex') == '1'
            is_edge = cell.get('edge') == '1'

            # Clean HTML from labels for text checking
            clean_val = re.sub(r'<[^>]+>', ' ', val)
            
            if is_edge:
                result["edges_count"] += 1
            
            if is_vertex and val:
                result["labels"].append(clean_val)

                # Check Metadata columns (HashKey, LoadDate, RecordSource)
                # These might be in the label of the entity or separate attribute shapes
                if "hashkey" in clean_val or "loaddate" in clean_val or "recordsource" in clean_val:
                    result["metadata_columns_found"] += 1

                # Classify Entity Types based on Name/Label
                # Hubs
                if "hub" in clean_val:
                    result["hubs_found"] += 1
                    # Check color (Blue #dae8fc)
                    if "#dae8fc" in style or "blue" in style:
                        result["hub_colors_correct"] += 1
                
                # Links
                elif "link" in clean_val:
                    result["links_found"] += 1
                    # Check color (Red/Pink #f8cecc)
                    if "#f8cecc" in style or "red" in style or "pink" in style:
                        result["link_colors_correct"] += 1
                
                # Satellites
                elif "sat" in clean_val:
                    result["sats_found"] += 1
                    # Check color (Yellow #fff2cc)
                    if "#fff2cc" in style or "yellow" in style or "gold" in style:
                        result["sat_colors_correct"] += 1

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Construct Final JSON
# Merge shell variables and python analysis
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "png_exists": $PNG_EXISTS,
    "file_size": $FILE_SIZE,
    "analysis": $(cat /tmp/dv_analysis.json)
}
EOF

echo "Result saved to /tmp/task_result.json"