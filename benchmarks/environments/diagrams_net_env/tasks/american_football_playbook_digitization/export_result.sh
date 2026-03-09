#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DRAWIO_FILE="/home/ga/Diagrams/playbook_template.drawio"
EXPORT_PDF="/home/ga/Diagrams/exports/spider_2_y_banana.pdf"
RESULT_JSON="/tmp/task_result.json"

# 1. Check Output PDF
PDF_EXISTS="false"
PDF_SIZE="0"
if [ -f "$EXPORT_PDF" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$EXPORT_PDF")
fi

# 2. Analyze Drawio XML Content
# We use a python script to parse the uncompressed XML part of the .drawio file
# Note: draw.io files are often XML, sometimes compressed. The template we made is uncompressed XML.
# If the agent saves it, it might become compressed. We need to handle that.

cat > /tmp/analyze_drawio.py << 'PYEOF'
import sys
import xml.etree.ElementTree as ET
import urllib.parse
import base64
import zlib
import json
import os
import re

file_path = sys.argv[1]
result = {
    "shapes": [],
    "labels": [],
    "edges": [],
    "is_compressed": False,
    "parse_error": False
}

if not os.path.exists(file_path):
    print(json.dumps(result))
    sys.exit(0)

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    # Handle compressed draw.io files
    diagram_node = root.find('diagram')
    xml_content = None
    
    if diagram_node is not None:
        if diagram_node.text and len(diagram_node.text.strip()) > 0:
            try:
                # Decode: Base64 -> Inflate -> URLDecode (standard draw.io compression)
                # Or sometimes just Base64 -> Inflate
                raw_data = base64.b64decode(diagram_node.text)
                try:
                    xml_content = zlib.decompress(raw_data, -15).decode('utf-8')
                    xml_content = urllib.parse.unquote(xml_content)
                except:
                    # Fallback for different compression
                    xml_content = zlib.decompress(raw_data).decode('utf-8')
                    xml_content = urllib.parse.unquote(xml_content)
                
                result["is_compressed"] = True
                root = ET.fromstring(xml_content)
            except Exception as e:
                # If decompression fails, it might be raw XML inside the node or just invalid
                pass

    # Find all cells
    for cell in root.findall(".//mxCell"):
        style = cell.get('style', '')
        value = cell.get('value', '')
        parent = cell.get('parent', '')
        
        # Skip palette items (usually have specific parents or positions, but hard to distinguish purely by XML 
        # without geometry. We assume items on the field (parent=1 usually) are relevant).
        
        item = {
            "id": cell.get('id'),
            "value": value,
            "style": style,
            "vertex": cell.get('vertex') == '1',
            "edge": cell.get('edge') == '1'
        }
        
        if item["vertex"]:
            result["shapes"].append(item)
            if value:
                # Clean label (remove HTML tags if any)
                clean_label = re.sub('<[^<]+?>', '', value).strip()
                result["labels"].append(clean_label)
                
        if item["edge"]:
            result["edges"].append(item)

except Exception as e:
    result["parse_error"] = str(e)

print(json.dumps(result))
PYEOF

# Run analysis
ANALYSIS=$(python3 /tmp/analyze_drawio.py "$DRAWIO_FILE")

# 3. Check file modification
FILE_MODIFIED="false"
if [ -f "$DRAWIO_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Construct JSON result
# Use a temporary file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "file_modified": $FILE_MODIFIED,
    "diagram_analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"
rm -f "$TEMP_JSON"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to $RESULT_JSON"