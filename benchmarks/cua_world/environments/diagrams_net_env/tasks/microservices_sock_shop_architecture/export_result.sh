#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Analyze the .drawio file (handles XML and Compression)
cat > /tmp/analyze_diagram.py << 'PY_EOF'
import sys
import os
import zlib
import base64
import json
import urllib.parse
import xml.etree.ElementTree as ET

def decode_diagram_data(encoded_data):
    try:
        # draw.io encoding: URI encode -> Base64 -> Deflate (no header)
        # We need to reverse this.
        # 1. URI Decode
        decoded_uri = urllib.parse.unquote(encoded_data)
        # 2. Base64 Decode
        compressed_data = base64.b64decode(decoded_uri)
        # 3. Inflate (raw deflate, no header -> wbits=-15)
        xml_data = zlib.decompress(compressed_data, -15)
        return xml_data.decode('utf-8')
    except Exception as e:
        return None

def analyze_file(filepath):
    if not os.path.exists(filepath):
        return {"exists": False}
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
    except Exception as e:
        return {"exists": True, "valid_xml": False, "error": str(e)}

    # Check if it's a compressed file or plain XML
    diagrams = root.findall('diagram')
    all_content = ""
    
    if diagrams:
        for d in diagrams:
            if d.text:
                # Try to decode
                decoded = decode_diagram_data(d.text)
                if decoded:
                    all_content += decoded
                else:
                    # Might be plain text or uncompressed?
                    all_content += d.text
    else:
        # Maybe it's directly uncompressed (older format or direct save)
        all_content = ET.tostring(root, encoding='unicode')

    # Now parse the aggregated content to find cells
    # We wrap it in a root tag to make it valid XML for parsing if it's just fragments
    try:
        # Simple string analysis usually suffices for counting and labels
        # finding vertex="1" and edge="1"
        pass
    except:
        pass

    # Basic String Counting (Robust against XML structure variations)
    # 1. Shape Count (vertex="1")
    shape_count = all_content.count('vertex="1"')
    
    # 2. Edge Count (edge="1")
    edge_count = all_content.count('edge="1"')
    
    # 3. Label Extraction (value="...")
    # This is a bit rough with regex/string, but works for verification
    content_lower = all_content.lower()
    
    services = ["catalogue", "carts", "orders", "payment", "user", "shipping", "queue-master"]
    found_services = [s for s in services if s in content_lower]
    
    dbs = ["catalogue-db", "carts-db", "orders-db", "user-db"]
    found_dbs = [d for d in dbs if d in content_lower]
    
    queue = ["rabbitmq"]
    found_queue = [q for q in queue if q in content_lower]
    
    protocols = ["http", "tcp", "amqp"]
    found_protocols = [p for p in protocols if p in content_lower]
    
    # 4. Color Extraction (fillColor=...)
    # Find unique fill colors
    import re
    colors = set(re.findall(r'fillColor=(#[0-9A-Fa-f]{6})', all_content))

    return {
        "exists": True,
        "valid_xml": True,
        "shape_count": shape_count,
        "edge_count": edge_count,
        "found_services": found_services,
        "found_dbs": found_dbs,
        "found_queue": found_queue,
        "found_protocols": found_protocols,
        "unique_colors": list(colors),
        "file_size": os.path.getsize(filepath)
    }

results = analyze_file("/home/ga/Diagrams/sock_shop_architecture.drawio")
print(json.dumps(results))
PY_EOF

# 3. Run Analysis
ANALYSIS_JSON=$(python3 /tmp/analyze_diagram.py)

# 4. Check Exports
SVG_EXISTS="false"
PNG_EXISTS="false"
[ -f "/home/ga/Diagrams/exports/sock_shop_architecture.svg" ] && SVG_EXISTS="true"
[ -f "/home/ga/Diagrams/exports/sock_shop_architecture.png" ] && PNG_EXISTS="true"

# 5. Check File Modification
FILE_MTIME=$(stat -c %Y /home/ga/Diagrams/sock_shop_architecture.drawio 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MODIFIED="false"
if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
    MODIFIED="true"
fi

# 6. Create Final JSON
cat > /tmp/task_result.json << JSON_EOF
{
    "diagram_analysis": $ANALYSIS_JSON,
    "svg_exported": $SVG_EXISTS,
    "png_exported": $PNG_EXISTS,
    "file_modified": $MODIFIED,
    "task_start_time": $START_TIME,
    "file_mtime": $FILE_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
JSON_EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json