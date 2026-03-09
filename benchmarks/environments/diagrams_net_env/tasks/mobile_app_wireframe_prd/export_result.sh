#!/bin/bash
set -e
echo "=== Exporting mobile app wireframe task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Diagrams/transit_app_wireframe.drawio"
PNG_FILE="/home/ga/Diagrams/transit_app_wireframe.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if draw.io file exists and was modified
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

# Check PNG export
PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# Python script to parse the drawio file (which might be compressed XML)
# and extract metrics about pages, shapes, edges, and text content.
cat > /tmp/analyze_drawio.py << 'PYEOF'
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import json
import re

def decode_diagram_data(encoded):
    try:
        # Decode URI component
        decoded = urllib.parse.unquote(encoded)
        # Base64 decode
        decoded = base64.b64decode(decoded)
        # Deflate (skip first bytes if needed, usually raw deflate)
        try:
            return zlib.decompress(decoded, -15).decode('utf-8')
        except:
            return zlib.decompress(decoded).decode('utf-8')
    except Exception as e:
        return None

def analyze_file(filepath):
    result = {
        "page_count": 0,
        "page_names": [],
        "total_shapes": 0,
        "total_edges": 0,
        "all_text": "",
        "error": None
    }
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Determine if file is compressed
        # <mxfile><diagram>ENCODED_BLOB</diagram></mxfile>
        diagrams = root.findall('diagram')
        result["page_count"] = len(diagrams)
        
        all_xml_content = ""
        
        for d in diagrams:
            result["page_names"].append(d.get('name', ''))
            if d.text and len(d.text.strip()) > 0:
                decoded = decode_diagram_data(d.text)
                if decoded:
                    all_xml_content += decoded
                else:
                    # Maybe it's not compressed?
                    all_xml_content += d.text
            else:
                # If content is inside children (uncompressed file)
                all_xml_content += ET.tostring(d, encoding='unicode')
        
        # Now parse the combined content to count things
        # Naive regex counting is often robust enough for stats
        # Shapes (vertices)
        result["total_shapes"] = len(re.findall(r'vertex="1"', all_xml_content))
        # Edges
        result["total_edges"] = len(re.findall(r'edge="1"', all_xml_content))
        
        # Extract text (label values)
        # value="Some Text"
        values = re.findall(r'value="([^"]*)"', all_xml_content)
        # Also clean up HTML entities
        clean_values = [re.sub(r'<[^>]+>', ' ', v) for v in values]
        result["all_text"] = " ".join(clean_values).lower()
        
    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    filepath = sys.argv[1]
    analysis = analyze_file(filepath)
    print(json.dumps(analysis))
PYEOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_drawio.py "$DRAWIO_FILE")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="