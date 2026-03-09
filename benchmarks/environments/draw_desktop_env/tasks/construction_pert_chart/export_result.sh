#!/bin/bash
# export_result.sh for construction_pert_chart
# Does NOT use set -e to allow robust error handling and partial result extraction

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/pert_chart.drawio"
PNG_FILE="/home/ga/Desktop/pert_chart.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Files
FILE_EXISTS="false"
FILE_MODIFIED="false"
PNG_EXISTS="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# 2. Analyze draw.io XML content using Python
# This script extracts nodes, edges, and checks for specific styling on edges
python3 << 'EOF' > /tmp/graph_analysis.json
import sys
import os
import base64
import zlib
import xml.etree.ElementTree as ET
import json
import re
from urllib.parse import unquote

filepath = "/home/ga/Desktop/pert_chart.drawio"

result = {
    "nodes": [],
    "edges": [],
    "critical_path_highlighted": False,
    "non_critical_highlighted": False,
    "error": None
}

def decode_diagram(root):
    # draw.io often compresses the XML inside a <diagram> tag
    diagram_node = root.find('diagram')
    if diagram_node is not None and diagram_node.text:
        try:
            # Try standard base64 + inflate
            decoded = base64.b64decode(diagram_node.text)
            xml_str = zlib.decompress(decoded, -15).decode('utf-8')
            return ET.fromstring(f"<root>{unquote(xml_str)}</root>")
        except Exception as e:
            # Sometimes it's just URL encoded or raw
            return None
    return root

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Attempt to decode compressed content if present
        content = decode_diagram(root)
        if content is None:
            content = root

        # Parse Cells
        # Vertices (Nodes)
        for cell in content.iter('mxCell'):
            if cell.get('vertex') == '1':
                val = cell.get('value', '')
                # Strip HTML
                clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
                if clean_val:
                    result['nodes'].append(clean_val)
            
            # Edges
            if cell.get('edge') == '1':
                source = cell.get('source', '')
                target = cell.get('target', '')
                style = cell.get('style', '')
                
                # Check for highlighting styles
                # Red color or thick stroke
                is_red = 'FF0000' in style or 'red' in style.lower() or 'strokeColor=#FF0000' in style
                is_thick = False
                stroke_width_match = re.search(r'strokeWidth=(\d+)', style)
                if stroke_width_match:
                    if int(stroke_width_match.group(1)) >= 3:
                        is_thick = True
                
                edge_info = {
                    'source_id': source,
                    'target_id': target,
                    'is_highlighted': (is_red and is_thick),
                    'is_red': is_red,
                    'is_thick': is_thick
                }
                result['edges'].append(edge_info)
        
        # Map IDs to Node Names to verify topology
        # We need to do a second pass or store ID mapping
        id_to_name = {}
        for cell in content.iter('mxCell'):
            if cell.get('vertex') == '1':
                clean_val = re.sub(r'<[^>]+>', ' ', cell.get('value', '')).strip()
                if clean_val:
                    id_to_name[cell.get('id')] = clean_val
        
        # Hydrate edge names
        final_edges = []
        for e in result['edges']:
            src_name = id_to_name.get(e['source_id'], "Unknown")
            tgt_name = id_to_name.get(e['target_id'], "Unknown")
            e['source_name'] = src_name
            e['target_name'] = tgt_name
            final_edges.append(e)
        result['edges'] = final_edges

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
EOF

# 3. Create final result JSON
# Combining shell checks and python analysis
jq -n \
    --arg exists "$FILE_EXISTS" \
    --arg modified "$FILE_MODIFIED" \
    --arg png_exists "$PNG_EXISTS" \
    --slurpfile graph /tmp/graph_analysis.json \
    '{
        file_exists: ($exists == "true"),
        file_modified: ($modified == "true"),
        png_exists: ($png_exists == "true"),
        graph_data: $graph[0]
    }' > /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="