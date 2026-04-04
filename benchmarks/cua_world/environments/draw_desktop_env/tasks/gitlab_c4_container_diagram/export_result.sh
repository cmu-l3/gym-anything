#!/bin/bash
# Do NOT use set -e

echo "=== Exporting GitLab C4 Diagram Result ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DRAWIO_FILE="/home/ga/Desktop/gitlab_c4_diagram.drawio"
PNG_FILE="/home/ga/Desktop/gitlab_c4_diagram.png"

# 2. Check File Existence & Timestamp
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

# 3. Analyze Diagram Content (XML Parsing)
# This Python script handles both uncompressed XML and draw.io's compressed XML format
python3 << 'EOF' > /tmp/diagram_analysis.json
import sys, zlib, base64, re, json, os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/gitlab_c4_diagram.drawio"
result = {
    "num_pages": 0,
    "num_shapes": 0,
    "num_edges": 0,
    "found_components": [],
    "found_protocols": [],
    "has_boundary": False,
    "has_actors": False,
    "error": None
}

REQUIRED_COMPONENTS = [
    "workhorse", "puma", "sidekiq", "gitaly", "shell", 
    "postgresql", "redis", "object storage", "registry", "prometheus"
]

PROTOCOLS = ["https", "grpc", "tcp", "ssh", "smtp"]

def decode_diagram(text):
    if not text: return None
    try:
        # Try Base64 + Deflate (standard draw.io compression)
        decoded = base64.b64decode(text)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except:
        try:
            # Try URL encoded
            return unquote(text)
        except:
            return None

if not os.path.exists(filepath):
    result["error"] = "File not found"
    print(json.dumps(result))
    sys.exit(0)

try:
    tree = ET.parse(filepath)
    root = tree.getroot()
    
    diagrams = root.findall('diagram')
    result["num_pages"] = len(diagrams)
    
    all_text = ""
    
    # Process each page
    for d in diagrams:
        content = d.text
        xml_content = decode_diagram(content)
        
        if xml_content:
            try:
                page_root = ET.fromstring(xml_content)
                # Count shapes and edges
                for cell in page_root.iter('mxCell'):
                    val = str(cell.get('value', '')).lower()
                    style = str(cell.get('style', '')).lower()
                    
                    if cell.get('vertex') == '1':
                        result["num_shapes"] += 1
                        all_text += " " + val
                        
                        # Detect boundary/group
                        if 'group' in style or 'swimlane' in style or 'container' in style:
                            result["has_boundary"] = True
                            
                        # Detect actors
                        if 'actor' in style or 'person' in style or 'shape=mxgraph.c4.person' in style:
                            result["has_actors"] = True
                            
                    elif cell.get('edge') == '1':
                        result["num_edges"] += 1
                        all_text += " " + val

            except Exception as e:
                pass
        else:
            # Maybe uncompressed directly in mxGraphModel?
            pass

    # Check for components in text
    all_text = all_text.lower()
    for comp in REQUIRED_COMPONENTS:
        if comp in all_text:
            result["found_components"].append(comp)
            
    # Check for protocols
    for proto in PROTOCOLS:
        if proto in all_text:
            result["found_protocols"].append(proto)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# 4. Create final result JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/diagram_analysis.json)
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json