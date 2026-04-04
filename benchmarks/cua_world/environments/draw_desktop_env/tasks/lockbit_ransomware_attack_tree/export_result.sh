#!/bin/bash
set -u

echo "=== Exporting lockbit_ransomware_attack_tree result ==="

# Paths
DRAWIO_FILE="/home/ga/Desktop/lockbit_attack_tree.drawio"
PNG_FILE="/home/ga/Desktop/lockbit_attack_tree.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check Files
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

# Analyze draw.io XML content using Python
# (Handles compressed/uncompressed XML and extracts stats)
cat > /tmp/analyze_drawio.py << 'EOF'
import sys
import os
import zlib
import base64
import json
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

def decode_diagram(content):
    if not content: return ""
    # Try raw XML
    if content.strip().startswith("<"):
        return content
    # Try Base64 + Inflate (draw.io standard compression)
    try:
        decoded = base64.b64decode(content)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except:
        pass
    # Try URL encoded
    try:
        return unquote(content)
    except:
        return content

filepath = sys.argv[1]
result = {
    "node_count": 0,
    "edge_count": 0,
    "text_content": [],
    "colors_used": [],
    "mitre_ids_found": [],
    "is_compressed": False
}

if not os.path.exists(filepath):
    print(json.dumps(result))
    sys.exit(0)

try:
    tree = ET.parse(filepath)
    root = tree.getroot()
    
    # Iterate over diagrams (pages)
    for diagram in root.findall("diagram"):
        raw_text = diagram.text
        xml_content = decode_diagram(raw_text)
        
        if xml_content and xml_content.startswith("<"):
            result["is_compressed"] = True
            try:
                # Parse the inner XML
                mx_graph = ET.fromstring(xml_content)
                root_model = mx_graph.find(".//root")
                if root_model is not None:
                    # Iterate cells
                    for cell in root_model.findall("mxCell"):
                        # Extract attributes
                        value = cell.get("value", "")
                        style = cell.get("style", "")
                        is_vertex = cell.get("vertex") == "1"
                        is_edge = cell.get("edge") == "1"
                        
                        if is_vertex:
                            result["node_count"] += 1
                        if is_edge:
                            result["edge_count"] += 1
                            
                        # Text analysis
                        if value:
                            # Strip HTML tags
                            clean_text = re.sub('<[^<]+?>', '', value)
                            result["text_content"].append(clean_text)
                            
                            # Find MITRE IDs (Txxxx)
                            mitre_ids = re.findall(r'T\d{4}(?:\.\d{3})?', clean_text)
                            result["mitre_ids_found"].extend(mitre_ids)
                            
                        # Color analysis (fillColor=#XXXXXX or strokeColor)
                        fill_match = re.search(r'fillColor=(#[0-9a-fA-F]{6}|[a-zA-Z]+)', style)
                        if fill_match:
                            result["colors_used"].append(fill_match.group(1))
            except Exception as e:
                pass
        else:
            # Handle uncompressed file format directly
            pass 
            # (Note: draw.io usually wraps in <diagram>, but if saved uncompressed, 
            # logic is similar but directly on root. For simplicity, we assume standard save format)

    # Fallback for uncompressed direct saves (if <diagram> tag logic failed or wasn't used)
    if result["node_count"] == 0:
        for cell in root.iter("mxCell"):
            value = cell.get("value", "")
            style = cell.get("style", "")
            if cell.get("vertex") == "1":
                result["node_count"] += 1
            if cell.get("edge") == "1":
                result["edge_count"] += 1
            if value:
                clean_text = re.sub('<[^<]+?>', '', value)
                result["text_content"].append(clean_text)
                mitre_ids = re.findall(r'T\d{4}(?:\.\d{3})?', clean_text)
                result["mitre_ids_found"].extend(mitre_ids)
            fill_match = re.search(r'fillColor=(#[0-9a-fA-F]{6}|[a-zA-Z]+)', style)
            if fill_match:
                result["colors_used"].append(fill_match.group(1))

    result["colors_used"] = list(set(result["colors_used"]))
    result["mitre_ids_found"] = list(set(result["mitre_ids_found"]))
    
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_drawio.py "$DRAWIO_FILE")
fi

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "analysis": $ANALYSIS_JSON,
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"