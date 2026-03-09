#!/bin/bash
# Do NOT use set -e

echo "=== Exporting mbta_subway_schematic result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/mbta_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/mbta_map.drawio"
PNG_FILE="/home/ga/Desktop/mbta_map.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check File Existence & Timestamp
FILE_EXISTS="false"
FILE_MODIFIED_AFTER_START="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
    echo "Found drawio file: $DRAWIO_FILE ($FILE_SIZE bytes)"
fi

PNG_EXISTS="false"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    echo "Found PNG file: $PNG_FILE"
fi

# 2. Parse Diagram Content (Python)
# This script decompresses the draw.io XML and builds a graph of nodes/edges/colors
python3 << 'PYEOF' > /tmp/mbta_analysis.json 2>/dev/null || true
import json
import re
import os
import base64
import zlib
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/mbta_map.drawio"
result = {
    "stations_found": [],
    "connections": [],
    "error": None
}

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

def normalize_name(name):
    if not name: return ""
    # Remove HTML tags
    name = re.sub(r'<[^>]+>', '', name)
    # Normalize whitespace and case
    return " ".join(name.lower().split())

TARGET_STATIONS = {
    "park street", "downtown crossing", "state", "government center",
    "haymarket", "north station", "south station"
}

try:
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Get all cells (handling compression)
        all_cells = []
        pages = root.findall('.//diagram')
        if not pages:
            # Maybe uncompressed root
            all_cells = list(root.iter('mxCell'))
        else:
            for page in pages:
                # Try inline
                cells = list(page.iter('mxCell'))
                if cells:
                    all_cells.extend(cells)
                else:
                    # Try compressed
                    inner = decompress_diagram(page.text or '')
                    if inner is not None:
                        all_cells.extend(list(inner.iter('mxCell')))

        # Build ID -> Label map for Nodes
        id_to_label = {}
        edges = []

        for cell in all_cells:
            cid = cell.get('id')
            val = cell.get('value', '')
            style = cell.get('style', '')
            
            # Is it a vertex (Node)?
            if cell.get('vertex') == '1':
                norm_label = normalize_name(val)
                # Check fuzzy match against target stations
                for target in TARGET_STATIONS:
                    if target in norm_label:
                        id_to_label[cid] = target
                        result["stations_found"].append(target)
                        break
            
            # Is it an edge?
            elif cell.get('edge') == '1':
                source = cell.get('source')
                target = cell.get('target')
                if source and target:
                    # Extract color from style
                    color = None
                    # format: strokeColor=#DA291C;
                    color_match = re.search(r'strokeColor=(#[0-9a-fA-F]{6})', style)
                    if color_match:
                        color = color_match.group(1).upper()
                    edges.append({
                        "source": source,
                        "target": target,
                        "color": color
                    })

        result["stations_found"] = list(set(result["stations_found"]))

        # Resolve edges to station names
        for edge in edges:
            src_label = id_to_label.get(edge['source'])
            tgt_label = id_to_label.get(edge['target'])
            if src_label and tgt_label:
                # Store connection as sorted tuple to be direction-agnostic
                conn_pair = sorted([src_label, tgt_label])
                result["connections"].append({
                    "u": conn_pair[0],
                    "v": conn_pair[1],
                    "color": edge['color']
                })

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/mbta_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="