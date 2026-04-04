#!/bin/bash
echo "=== Exporting Threat Model Task Results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
DRAWIO_FILE="/home/ga/Diagrams/threat_model.drawio"
PDF_FILE="/home/ga/Diagrams/threat_model.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check file existence and timestamps
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

PDF_EXISTS="false"
if [ -f "$PDF_FILE" ]; then
    PDF_SIZE=$(stat -c %s "$PDF_FILE")
    if [ "$PDF_SIZE" -gt 1000 ]; then # Valid PDF usually > 1KB
        PDF_EXISTS="true"
    fi
fi

# 4. Analyze the .drawio file content (XML parsing using embedded Python)
# We need to handle potentially compressed content
cat > /tmp/analyze_drawio.py << 'EOF'
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import json

def decode_drawio_content(encoded_text):
    try:
        # Standard draw.io compression: URL encoded -> Base64 -> Deflate (no header)
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded)
        # -15 for raw deflate (no zlib header)
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        return None

def analyze(file_path):
    result = {
        "page_count": 0,
        "shape_count": 0,
        "edge_count": 0,
        "labels": [],
        "trust_boundaries": 0,
        "has_summary_page": False
    }

    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception as e:
        return result

    # Check if this is a standard mxfile
    if root.tag != 'mxfile':
        return result

    diagrams = root.findall('diagram')
    result["page_count"] = len(diagrams)

    all_cells = []

    for diag in diagrams:
        # Check for summary page name
        name = diag.get('name', '').lower()
        if 'summary' in name or 'threat' in name:
            result["has_summary_page"] = True

        # Decode content if compressed
        if diag.text and diag.text.strip():
            xml_content = decode_drawio_content(diag.text)
            if xml_content:
                try:
                    diag_root = ET.fromstring(xml_content)
                    all_cells.extend(diag_root.findall('.//mxCell'))
                except:
                    pass
        else:
            # Maybe uncompressed directly inside (less common for multi-page but possible)
            all_cells.extend(diag.findall('.//mxCell'))

    # If no diagrams found but mxGraphModel exists directly (legacy/single page uncompressed)
    if not diagrams and root.find('.//mxGraphModel'):
        all_cells.extend(root.findall('.//mxCell'))
        result["page_count"] = 1

    # Analyze cells
    for cell in all_cells:
        value = str(cell.get('value', '')).lower()
        style = str(cell.get('style', '')).lower()
        is_vertex = cell.get('vertex') == '1'
        is_edge = cell.get('edge') == '1'

        if is_vertex:
            result["shape_count"] += 1
            if value:
                result["labels"].append(value)
            
            # Trust boundary detection (dashed lines, containers, groups)
            if 'dashed=1' in style or 'dashpattern' in style:
                # Often trust boundaries are empty containers or groups
                result["trust_boundaries"] += 1
            elif 'boundary' in value or 'trust' in value or 'zone' in value:
                result["trust_boundaries"] += 1

        if is_edge:
            result["edge_count"] += 1
            if value:
                result["labels"].append(value)

    return result

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No file provided"}))
        sys.exit(1)
    
    analysis = analyze(sys.argv[1])
    print(json.dumps(analysis))
EOF

# Run analysis
if [ "$FILE_EXISTS" = "true" ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_drawio.py "$DRAWIO_FILE")
else
    ANALYSIS_JSON='{"page_count": 0, "shape_count": 0, "edge_count": 0, "labels": [], "trust_boundaries": 0, "has_summary_page": false}'
fi

# 5. Compile Final JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "pdf_exists": $PDF_EXISTS,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"