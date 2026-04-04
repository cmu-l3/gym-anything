#!/bin/bash
echo "=== Exporting ICS Purdue Model Segmentation Results ==="

# 1. Capture timestamps and final state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check PDF Export
PDF_PATH="/home/ga/Diagrams/exports/purdue_network.pdf"
PDF_EXISTS="false"
PDF_SIZE=0
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
fi

# 3. Analyze the .drawio XML structure using Python
# We need to map: Container Label -> List of Contained Devices
DIAGRAM_PATH="/home/ga/Diagrams/factory_audit.drawio"

cat << 'PY_EOF' > /tmp/analyze_drawio.py
import sys
import xml.etree.ElementTree as ET
import json
import base64
import zlib
import urllib.parse
import re

def decode_drawio(content):
    """Decompress draw.io XML if it's compressed"""
    try:
        # Check if it looks like standard XML first
        if content.strip().startswith('<mxfile'):
            tree = ET.fromstring(content)
            # If it has a <diagram> tag with text content, it might be compressed
            diagram = tree.find('diagram')
            if diagram is not None and diagram.text:
                # Compressed data
                data = base64.b64decode(diagram.text)
                xml_str = zlib.decompress(data, -15).decode('utf-8')
                return urllib.parse.unquote(xml_str)
            return content
    except Exception as e:
        return content # Return original if decode fails
    return content

def analyze_diagram(file_path):
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        xml_content = decode_drawio(content)
        # Parse XML (handle potential encoded inner XML)
        try:
            root = ET.fromstring(xml_content)
        except ET.ParseError:
            # Fallback for double-wrapped
             root = ET.fromstring(content)

        # Flatten all cells
        cells = []
        # Handle both structure types (mxGraphModel inside diagram or direct)
        if root.tag == 'mxGraphModel':
             cells = root.findall(".//mxCell")
        else:
             cells = root.findall(".//mxCell")

        # 1. Identify Containers/Swimlanes
        containers = {} # ID -> Label
        # 2. Identify Devices and their parents
        devices = {} # ID -> {label: str, parent: str}
        # 3. Identify Firewalls
        firewall_count = 0
        
        for cell in cells:
            cid = cell.get('id')
            val = cell.get('value', '')
            style = cell.get('style', '')
            parent = cell.get('parent', '')
            
            # Normalize strings
            val_lower = val.lower()
            style_lower = style.lower()
            
            # Heuristic for Containers: often have 'swimlane' or 'group' in style, or are just large boxes with specific labels
            # We look for the level labels
            is_container = False
            if 'swimlane' in style_lower or 'container' in style_lower or 'group' in style_lower:
                is_container = True
            
            # Also check text if it looks like a level label
            if any(x in val_lower for x in ['level 4', 'level 3', 'level 2', 'level 1', 'dmz', 'enterprise', 'operations', 'control']):
                is_container = True
            
            if is_container:
                containers[cid] = val_lower
            
            # Heuristic for Firewalls
            if 'firewall' in val_lower or 'firewall' in style_lower:
                firewall_count += 1
            
            # Track all items that have parents
            if parent and parent != '0' and parent != '1':
                devices[cid] = {'label': val_lower, 'parent': parent}

        # 4. Map Devices to Container Labels
        # We need to resolve the parent ID to the container label
        results = {
            "containers_found": list(containers.values()),
            "device_placements": [],
            "firewall_count": firewall_count
        }
        
        for did, info in devices.items():
            parent_id = info['parent']
            # Sometimes nesting is deep (Group -> Swimlane). We check immediate parent.
            # In a robust check we might traverse up, but immediate parent is usually enough for single-layer nesting.
            if parent_id in containers:
                container_label = containers[parent_id]
                results["device_placements"].append({
                    "device": info['label'],
                    "container": container_label
                })
        
        print(json.dumps(results))
        
    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    analyze_diagram(sys.argv[1])
PY_EOF

# Run analysis
echo "Running diagram analysis..."
ANALYSIS_JSON=$(python3 /tmp/analyze_drawio.py "$DIAGRAM_PATH")

# 4. Compile Final Result JSON
cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "pdf_exists": $PDF_EXISTS,
  "pdf_size": $PDF_SIZE,
  "diagram_analysis": $ANALYSIS_JSON
}
EOF

# Set permissions for the verifier to read
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json