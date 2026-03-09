#!/bin/bash
echo "=== Exporting Hydraulic Circuit Task Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DIAGRAM_PATH="/home/ga/Diagrams/excavator_thumb_circuit.drawio"
PDF_PATH="/home/ga/Diagrams/excavator_thumb_circuit.pdf"

# 1. Take Final Screenshot
export DISPLAY=:1
scrot /tmp/task_final.png || true

# 2. Check Files
FILE_EXISTS="false"
PDF_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DIAGRAM_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DIAGRAM_PATH")
    FILE_MTIME=$(stat -c %Y "$DIAGRAM_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
fi

# 3. Analyze Diagram Content (Python)
# We need to decode the draw.io file (often compressed XML) and check for fluid power shapes
cat > /tmp/analyze_drawio.py << 'EOF'
import sys
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import json
import re

file_path = sys.argv[1]

result = {
    "shapes": [],
    "labels": [],
    "has_dashed_lines": False,
    "uses_fluid_library": False
}

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    xml_content = ""
    
    # Draw.io files can be plain XML or Compressed in a <diagram> tag
    diagrams = root.findall('diagram')
    if diagrams:
        for d in diagrams:
            if d.text:
                try:
                    # Decode flow: Base64 -> Inflate (no header) -> URL Decode (sometimes)
                    # Standard draw.io compression is Deflate (zlib)
                    data = base64.b64decode(d.text)
                    try:
                        xml_content += zlib.decompress(data, -15).decode('utf-8')
                    except:
                        # Sometimes it's just raw XML or different compression
                        xml_content += data.decode('utf-8')
                except Exception as e:
                    pass
    else:
        # Might be uncompressed XML directly
        xml_content = ET.tostring(root, encoding='unicode')

    # Parse the inner content
    # We are looking for specific style attributes
    # e.g., style="...mxgraph.fluid_power..."
    
    # Simple Regex checks are often more robust for 'style' strings than parsing inner XML fragments
    
    # Check for Library Usage
    if "mxgraph.fluid_power" in xml_content or "shape=mxgraph.fluid_power" in xml_content:
        result["uses_fluid_library"] = True
        
    # Check for Dashed Lines (dashed=1 in style)
    if "dashed=1" in xml_content:
        result["has_dashed_lines"] = True
        
    # Extract Labels (value="...")
    # Matches value="Label"
    labels = re.findall(r'value="([^"]+)"', xml_content)
    result["labels"] = [l for l in labels if l.strip()]
    
    # Identify Components by style keywords
    styles = re.findall(r'style="([^"]+)"', xml_content)
    for style in styles:
        if "pump" in style.lower(): result["shapes"].append("pump")
        if "valve" in style.lower(): result["shapes"].append("valve")
        if "cylinder" in style.lower(): result["shapes"].append("cylinder")
        if "tank" in style.lower() or "reservoir" in style.lower(): result["shapes"].append("tank")
        if "filter" in style.lower(): result["shapes"].append("filter")

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

ANALYSIS="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    ANALYSIS=$(python3 /tmp/analyze_drawio.py "$DIAGRAM_PATH")
fi

# 4. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "file_size": $FILE_SIZE,
    "analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"