#!/bin/bash
# Do NOT use set -e

echo "=== Exporting Active Directory Topology result ==="

# 1. Capture Final State
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
DRAWIO_FILE="/home/ga/Desktop/ad_topology.drawio"
PNG_FILE="/home/ga/Desktop/ad_topology.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Basic File Checks
FILE_EXISTS="false"
PNG_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# 4. Advanced Analysis using Python
# This script parses the .drawio XML (handling compression) to extract the graph structure
python3 << 'PYEOF' > /tmp/ad_topology_analysis.json 2>/dev/null || true
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

def decode_drawio_content(content):
    """Decompresses draw.io XML content."""
    if not content: return None
    try:
        # Try raw inflate
        decoded = base64.b64decode(content)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except:
        try:
            # Try URL decode
            return unquote(content)
        except:
            return content

def parse_drawio(filepath):
    result = {
        "nodes": [],          # {id, label, style}
        "edges": [],          # {source_id, target_id, label}
        "groups": [],         # {id, label}
        "forest_count": 0,
        "domain_count": 0,
        "triangle_shapes": 0
    }
    
    if not os.path.exists(filepath):
        return result

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Check for compressed diagram
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            xml_content = decode_drawio_content(diagram_node.text)
            if xml_content:
                try:
                    root = ET.fromstring(xml_content)
                except:
                    pass # Fallback to original root if parsing fails

        # Extract cells
        for cell in root.iter('mxCell'):
            c_id = cell.get('id')
            val = cell.get('value', '').strip()
            style = cell.get('style', '').lower()
            
            # Nodes (Vertices)
            if cell.get('vertex') == '1':
                # Check if it's a group/container (Forest)
                if 'group' in style or 'container' in style or 'swimlane' in style:
                    result["groups"].append({"id": c_id, "label": val})
                    result["forest_count"] += 1
                else:
                    # Regular node (Domain)
                    result["nodes"].append({"id": c_id, "label": val, "style": style})
                    if 'triangle' in style:
                        result["triangle_shapes"] += 1
                    
                    # Clean label for counting domains
                    if val and len(val) > 3: 
                        result["domain_count"] += 1

            # Edges
            elif cell.get('edge') == '1':
                source = cell.get('source')
                target = cell.get('target')
                if source and target:
                    result["edges"].append({
                        "source": source,
                        "target": target,
                        "label": val
                    })
                    
    except Exception as e:
        result["error"] = str(e)
        
    return result

analysis = parse_drawio("/home/ga/Desktop/ad_topology.drawio")
print(json.dumps(analysis))
PYEOF

# 5. Construct Final JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/ad_topology_analysis.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="