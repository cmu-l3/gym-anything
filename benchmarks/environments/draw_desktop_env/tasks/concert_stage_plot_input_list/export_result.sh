#!/bin/bash
echo "=== Exporting concert_stage_plot_input_list results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DRAWIO_FILE="/home/ga/Desktop/midnight_alibi_rider.drawio"
PNG_FILE="/home/ga/Desktop/midnight_alibi_rider.png"

# Check file existence and timestamps
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
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to analyze the draw.io XML content
# This extracts text labels and coordinates for the verifier
python3 << 'PYEOF' > /tmp/drawio_analysis.json
import json
import base64
import zlib
import xml.etree.ElementTree as ET
import os
from urllib.parse import unquote
import re

file_path = "/home/ga/Desktop/midnight_alibi_rider.drawio"
result = {
    "parsed": False,
    "shapes": [],
    "error": None
}

if os.path.exists(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Handle compressed diagram content (mxfile)
        diagrams = root.findall('diagram')
        xml_content_root = root
        
        if diagrams and diagrams[0].text:
            try:
                # Try standard deflate
                compressed_data = base64.b64decode(diagrams[0].text)
                xml_data = zlib.decompress(compressed_data, -15)
                xml_data = unquote(xml_data.decode('utf-8'))
                xml_content_root = ET.fromstring(xml_data)
            except Exception as e:
                # Fallback or raw xml
                pass

        # Extract shapes and text
        shapes = []
        for cell in xml_content_root.iter('mxCell'):
            # Get geometry
            geo = cell.find('mxGeometry')
            x, y = 0.0, 0.0
            if geo is not None:
                x = float(geo.get('x', 0))
                y = float(geo.get('y', 0))
            
            # Get text value
            val = cell.get('value', '')
            if val:
                # Strip HTML tags
                clean_text = re.sub('<[^<]+?>', ' ', val).strip()
                shapes.append({
                    "text": clean_text.lower(),
                    "raw_text": val,
                    "x": x,
                    "y": y
                })
        
        result["parsed"] = True
        result["shapes"] = shapes
        
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Combine info into final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/drawio_analysis.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"