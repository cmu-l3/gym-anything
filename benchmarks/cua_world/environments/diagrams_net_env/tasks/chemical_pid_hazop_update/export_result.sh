#!/bin/bash
set -e

echo "=== Exporting Chemical P&ID Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence and Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIAGRAM_FILE="/home/ga/Diagrams/methanol_storage.drawio"
EXPORT_FILE="/home/ga/Diagrams/methanol_storage_rev1.pdf"

EXPORT_EXISTS="false"
EXPORT_SIZE=0
if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE")
fi

FILE_MODIFIED="false"
if [ -f "$DIAGRAM_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$DIAGRAM_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Analyze Diagram Content (XML Parsing)
# We use Python inside the container to robustly parse the XML
# and identify shapes, styles, and text labels.

cat > /tmp/analyze_diagram.py << 'EOF'
import sys
import xml.etree.ElementTree as ET
import json
import re
import zlib
import base64
from urllib.parse import unquote

def decode_mxfile(text):
    """Decodes the compressed draw.io XML format."""
    try:
        # Standard draw.io compression: URL decode -> Base64 decode -> Inflate (zlib -15)
        data = base64.b64decode(unquote(text))
        xml = zlib.decompress(data, -15).decode('utf-8')
        return xml
    except Exception as e:
        return None

def analyze(file_path):
    result = {
        "shapes": [],
        "edges": [],
        "labels": [],
        "styles": [],
        "parse_error": False
    }
    
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Handle compressed diagrams (mxfile -> diagram -> mxGraphModel vs compressed text)
        diagrams = root.findall('diagram')
        if diagrams:
            # Iterate all pages, but usually there's just one
            for diag in diagrams:
                if diag.text and diag.text.strip():
                    decoded_xml = decode_mxfile(diag.text)
                    if decoded_xml:
                        # Parse the decoded inner XML
                        inner_root = ET.fromstring(decoded_xml)
                        cells = inner_root.findall(".//mxCell")
                    else:
                        cells = [] # Failed to decode
                else:
                    # Uncompressed inside diagram tag
                    cells = diag.findall(".//mxCell")
                
                process_cells(cells, result)
        else:
            # Direct mxGraphModel structure
            cells = root.findall(".//mxCell")
            process_cells(cells, result)
            
    except Exception as e:
        result["parse_error"] = str(e)
        
    return result

def process_cells(cells, result):
    for cell in cells:
        style = cell.get('style', '').lower()
        value = cell.get('value', '')
        edge = cell.get('edge', '0')
        vertex = cell.get('vertex', '0')
        source = cell.get('source')
        target = cell.get('target')

        # Clean label (remove HTML)
        clean_label = re.sub('<[^<]+?>', '', value).strip()
        
        if edge == '1':
            result['edges'].append({
                'source': source,
                'target': target,
                'style': style
            })
        elif vertex == '1':
            result['shapes'].append({
                'id': cell.get('id'),
                'label': clean_label,
                'style': style
            })
            if clean_label:
                result['labels'].append(clean_label)
            result['styles'].append(style)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No file provided"}))
        sys.exit(1)
        
    res = analyze(sys.argv[1])
    print(json.dumps(res))
EOF

# Run the analysis
if [ -f "$DIAGRAM_FILE" ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_diagram.py "$DIAGRAM_FILE")
else
    ANALYSIS_JSON='{"error": "File not found"}'
fi

# 4. Compile Final JSON Result
# Using jq if available, otherwise manual construction or python again
# We'll use a python one-liner to merge for safety

cat > /tmp/merge_results.py << EOF
import json
import sys

try:
    analysis = json.loads(sys.argv[1])
except:
    analysis = {}

result = {
    "task_start": $TASK_START,
    "export_exists": "$EXPORT_EXISTS" == "true",
    "export_size": $EXPORT_SIZE,
    "file_modified": "$FILE_MODIFIED" == "true",
    "diagram_analysis": analysis
}
print(json.dumps(result))
EOF

python3 /tmp/merge_results.py "$ANALYSIS_JSON" > /tmp/task_result.json

# 5. Cleanup
rm -f /tmp/analyze_diagram.py /tmp/merge_results.py

echo "Export complete. Result:"
cat /tmp/task_result.json