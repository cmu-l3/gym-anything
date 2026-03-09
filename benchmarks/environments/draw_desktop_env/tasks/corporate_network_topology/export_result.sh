#!/bin/bash
echo "=== Exporting Network Topology Result ==="

DRAWIO_FILE="/home/ga/Desktop/network_topology.drawio"
PNG_FILE="/home/ga/Desktop/network_topology.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Basic file checks
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# 3. Deep Analysis with Python
# Parses the XML to count devices, edges, zones, and pages
python3 << 'PYEOF' > /tmp/topology_analysis.json 2>/dev/null || true
import json
import os
import re
import base64
import zlib
import xml.etree.ElementTree as ET
from urllib.parse import unquote

file_path = "/home/ga/Desktop/network_topology.drawio"
devices_to_find = [
    "ISP-RTR-01", "EDGE-RTR-01", "FW-01", "DMZ-SW-01", "WEB-SRV-01", 
    "MAIL-GW-01", "DNS-EXT-01", "CORE-SW-01", "DIST-SW-F1", "DIST-SW-F2", 
    "SRV-SW-01", "AD-DC-01", "FILE-SRV-01", "DB-SRV-01", "APP-SRV-01", 
    "BKP-SRV-01", "WLC-01", "AP-F1-01", "AP-F2-01", "MGMT-SW-01", 
    "NMS-01", "SYSLOG-01", "RADIUS-01"
]
zones_to_find = ["WAN", "DMZ", "Core", "Server", "Wireless", "Management"]

result = {
    "num_shapes": 0,
    "num_edges": 0,
    "num_pages": 0,
    "found_devices": [],
    "found_zones": [],
    "has_ip_table": False,
    "text_content_length": 0,
    "error": None
}

def decode_diagram(text):
    if not text: return None
    # 1. Try URL decoded
    try:
        decoded = unquote(text)
        if decoded.strip().startswith('<'):
            return ET.fromstring(decoded)
    except: pass
    
    # 2. Try Base64 + Inflate (draw.io default)
    try:
        data = base64.b64decode(text)
        # -15 for raw deflate (no zlib header)
        decompressed = zlib.decompress(data, -15)
        return ET.fromstring(decompressed)
    except: pass
    
    return None

try:
    if os.path.exists(file_path):
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Count pages
        diagrams = root.findall('diagram')
        result["num_pages"] = len(diagrams)
        
        all_text = ""
        
        for diagram in diagrams:
            # Check for content inside diagram tag (compressed or plain)
            root_graph = None
            if diagram.text and diagram.text.strip():
                root_graph = decode_diagram(diagram.text)
            
            # If not compressed, might be children of diagram/mxGraphModel
            if root_graph is None:
                # Some formats have mxGraphModel directly under diagram
                model = diagram.find('mxGraphModel')
                if model is not None:
                    root_graph = model

            if root_graph is not None:
                # Iterate all cells
                for cell in root_graph.iter('mxCell'):
                    val = cell.get('value', '')
                    style = cell.get('style', '')
                    vertex = cell.get('vertex')
                    edge = cell.get('edge')
                    
                    if vertex == '1':
                        result["num_shapes"] += 1
                        all_text += " " + val
                        
                        # Check for Zones (Containers)
                        # Usually style contains 'swimlane' or 'group' or 'container'
                        # And value contains the zone name
                        is_container = 'swimlane' in style or 'group' in style or 'container' in style
                        if is_container:
                            for zone in zones_to_find:
                                if zone.lower() in val.lower():
                                    if zone not in result["found_zones"]:
                                        result["found_zones"].append(zone)

                    if edge == '1':
                        result["num_edges"] += 1
                        all_text += " " + val

        result["text_content_length"] = len(all_text)
        
        # Check for devices in collected text
        # Using simple string matching, could use regex for exact word match
        # normalizing text to handle HTML tags sometimes present in values
        clean_text = re.sub(r'<[^>]+>', ' ', all_text).upper()
        
        for dev in devices_to_find:
            if dev.upper() in clean_text:
                result["found_devices"].append(dev)
                
        # Check for IP table keywords
        if "ADDRESSING" in clean_text or "ALLOCATION" in clean_text or "SUBNET" in clean_text:
            result["has_ip_table"] = True

    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 4. Construct Final JSON
# Merge shell variables and Python analysis
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/topology_analysis.json)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json