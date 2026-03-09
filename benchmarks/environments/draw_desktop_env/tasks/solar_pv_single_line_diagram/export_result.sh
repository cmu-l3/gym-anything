#!/bin/bash
echo "=== Exporting Solar SLD Result ==="

# Timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File Paths
DRAWIO_FILE="/home/ga/Desktop/solar_sld.drawio"
PNG_FILE="/home/ga/Desktop/solar_sld.png"

# Check Files
DRAWIO_EXISTS="false"
PNG_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
PNG_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    F_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$F_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# Application Status
APP_RUNNING=$(pgrep -f "drawio" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ------------------------------------------------------------------
# Python XML Analysis for Component & Connectivity Verification
# ------------------------------------------------------------------
python3 << 'PYEOF' > /tmp/sld_analysis.json
import sys
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

def decode_drawio(content):
    """Decompress draw.io XML content."""
    try:
        # Try raw XML first
        if content.strip().startswith("<"):
            return ET.fromstring(content)
        # Try URL decoding
        try:
            decoded = unquote(content)
            if decoded.strip().startswith("<"):
                return ET.fromstring(decoded)
        except: pass
        # Try Base64 + Inflate (Standard draw.io compression)
        decoded_b64 = base64.b64decode(content)
        xml_str = zlib.decompress(decoded_b64, -15).decode('utf-8')
        return ET.fromstring(xml_str)
    except Exception as e:
        return None

def analyze_graph(filepath):
    result = {
        "text_content": [],
        "components_found": [],
        "edge_count": 0,
        "vertex_count": 0,
        "is_connected_pv_to_grid": False,
        "error": None
    }
    
    if not os.path.exists(filepath):
        result["error"] = "File not found"
        return result

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Handle multiple pages or compressed content
        diagrams = root.findall('diagram')
        if not diagrams:
            # Maybe it's just a raw mxGraphModel
            mx_root = root
        else:
            # Process first diagram
            d_content = diagrams[0].text
            mx_root = decode_drawio(d_content)
            if mx_root is None:
                # If compression fails, try to look for mxGraphModel inside
                mx_root = diagrams[0].find('mxGraphModel')

        if mx_root is None:
            result["error"] = "Could not parse diagram structure"
            return result

        # Build Graph
        # Nodes: id -> text
        # Edges: source_id -> [target_ids]
        nodes = {}
        adjacency = {}
        
        root_cell = mx_root.find('root')
        if root_cell is None:
             # Try searching deeper
             root_cell = mx_root.find('.//root')

        if root_cell is not None:
            for cell in root_cell:
                cid = cell.get('id')
                val = cell.get('value', '')
                style = cell.get('style', '')
                
                # Check for vertex
                if cell.get('vertex') == '1':
                    result["vertex_count"] += 1
                    
                    # Clean text (remove HTML)
                    text = re.sub(r'<[^>]+>', ' ', val).replace('&nbsp;', ' ')
                    nodes[cid] = text.lower()
                    result["text_content"].append(text)
                    
                    # Identify component types
                    lower_text = text.lower()
                    if 'pv' in lower_text or 'module' in lower_text or 'panel' in lower_text or 'q.peak' in lower_text:
                        result["components_found"].append("PV")
                    if 'inverter' in lower_text or 'se7600' in lower_text:
                        result["components_found"].append("Inverter")
                    if 'grid' in lower_text or 'utility' in lower_text:
                        result["components_found"].append("Grid")
                    if 'meter' in lower_text:
                        result["components_found"].append("Meter")
                    if 'breaker' in lower_text or 'panel' in lower_text or 'load center' in lower_text:
                         # Distinguish main panel from PV panel
                         if 'main' in lower_text or 'service' in lower_text or '200a' in lower_text:
                             result["components_found"].append("ServicePanel")
                    
                # Check for edge
                if cell.get('edge') == '1':
                    result["edge_count"] += 1
                    src = cell.get('source')
                    tgt = cell.get('target')
                    
                    if src and tgt:
                        if src not in adjacency: adjacency[src] = []
                        if tgt not in adjacency: adjacency[tgt] = []
                        # Undirected graph for simple connectivity check
                        adjacency[src].append(tgt)
                        adjacency[tgt].append(src)

        # BFS Connectivity Check: PV to Grid
        pv_nodes = [id for id, text in nodes.items() if 'pv' in text or 'module' in text or 'q.peak' in text]
        grid_nodes = [id for id, text in nodes.items() if 'grid' in text or 'utility' in text]
        
        connected = False
        if pv_nodes and grid_nodes:
            queue = [pv_nodes[0]]
            visited = set([pv_nodes[0]])
            
            while queue:
                current = queue.pop(0)
                # If current node is a grid node, we found a path
                if current in grid_nodes:
                    connected = True
                    break
                
                if current in adjacency:
                    for neighbor in adjacency[current]:
                        if neighbor not in visited:
                            visited.add(neighbor)
                            queue.append(neighbor)
        
        result["is_connected_pv_to_grid"] = connected

    except Exception as e:
        result["error"] = str(e)

    print(json.dumps(result))

if __name__ == "__main__":
    analyze_graph("/home/ga/Desktop/solar_sld.drawio")
PYEOF

# Combine Results
# We read the python output into a variable
ANALYSIS_JSON=$(cat /tmp/sld_analysis.json)

# Construct Final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_exists": $DRAWIO_EXISTS,
    "png_exists": $PNG_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "png_size_bytes": $PNG_SIZE,
    "app_was_running": $APP_RUNNING,
    "analysis": $ANALYSIS_JSON
}
EOF

# Fix permissions
chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"