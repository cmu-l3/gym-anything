#!/bin/bash
# Do NOT use set -e

echo "=== Exporting mobile_checkout_wireframe result ==="

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/checkout_flow.drawio"
PNG_FILE="/home/ga/Desktop/checkout_flow.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check Drawio File
DRAWIO_EXISTS="false"
DRAWIO_MODIFIED="false"
if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS="true"
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        DRAWIO_MODIFIED="true"
    fi
fi

# Check PNG File
PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# Deep Analysis of the .drawio file using Python
# This script handles decompression and parsing to extract content stats
python3 << 'PYEOF' > /tmp/wireframe_analysis.json 2>/dev/null || true
import json
import re
import os
import base64
import zlib
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/checkout_flow.drawio"
result = {
    "shape_count": 0,
    "edge_count": 0,
    "phone_frames_found": 0,
    "all_text": "",
    "error": None
}

def decode_drawio_content(content):
    """Decompress draw.io content (deflate+base64 or URL encoded)."""
    if not content: return None
    try:
        # Try standard compression
        decoded = base64.b64decode(content)
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        # Try URL decoding (sometimes used)
        decoded = unquote(content)
        if decoded.strip().startswith('<'):
            return ET.fromstring(decoded)
    except Exception:
        pass
    return None

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Draw.io files can be a wrapper <mxfile> containing compressed <diagram>
        # or a direct <mxGraphModel>
        
        all_cells = []
        
        # Check for compressed diagrams
        diagrams = root.findall('diagram')
        if diagrams:
            for d in diagrams:
                # Text content of <diagram> is usually compressed
                inner_root = decode_drawio_content(d.text)
                if inner_root is not None:
                    all_cells.extend(list(inner_root.iter('mxCell')))
                else:
                    # Maybe it wasn't compressed, just inline?
                    all_cells.extend(list(d.iter('mxCell')))
        else:
            # Maybe flat XML
            all_cells.extend(list(root.iter('mxCell')))

        # Stats collection
        text_content = []
        
        # Mobile shape keywords in 'style' attribute
        # e.g., 'mockup', 'phone', 'sl_iphone', 'android', 'mobile'
        phone_style_keywords = ['mockup', 'phone', 'iphone', 'android', 'mobile', 'smartphone']
        
        for cell in all_cells:
            style = (cell.get('style') or '').lower()
            val = (cell.get('value') or '').lower()
            
            # Vertex (Shape) vs Edge (Arrow)
            if cell.get('vertex') == '1':
                # Ignore the default parent/background cells
                if cell.get('id') in ['0', '1']: continue
                
                result["shape_count"] += 1
                
                # Check for phone frames
                if any(k in style for k in phone_style_keywords):
                    result["phone_frames_found"] += 1
                
                # Collect text (strip HTML)
                if val:
                    clean_val = re.sub(r'<[^>]+>', ' ', val)
                    text_content.append(clean_val)
                    
            elif cell.get('edge') == '1':
                result["edge_count"] += 1
                if val:
                    clean_val = re.sub(r'<[^>]+>', ' ', val)
                    text_content.append(clean_val)
        
        result["all_text"] = " ".join(text_content)

    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_modified": $DRAWIO_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis_path": "/tmp/wireframe_analysis.json"
}
EOF

# Merge the python analysis into the main json
python3 -c "import json; 
with open('$TEMP_JSON') as f: main = json.load(f); 
try:
    with open('/tmp/wireframe_analysis.json') as f: analysis = json.load(f)
    main.update(analysis)
except: pass; 
print(json.dumps(main))" > /tmp/task_result.json

# Clean up
rm -f "$TEMP_JSON" /tmp/wireframe_analysis.json

echo "Result exported to /tmp/task_result.json"