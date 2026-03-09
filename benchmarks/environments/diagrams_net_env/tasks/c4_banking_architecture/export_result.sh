#!/bin/bash
echo "=== Exporting C4 Architecture Task Result ==="

# Define paths
DRAWIO_FILE="/home/ga/Diagrams/banking_system_c4.drawio"
PDF_FILE="/home/ga/Diagrams/banking_system_c4.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper python script to parse .drawio file (which handles URL encoding and Deflate compression)
# We embed this here to avoid external dependency files
cat > /tmp/parse_drawio.py << 'PYEOF'
import sys
import json
import base64
import zlib
import urllib.parse
import os
import xml.etree.ElementTree as ET

def decode_drawio_content(encoded_text):
    """Decode standard draw.io compressed XML content."""
    try:
        # Standard draw.io encoding: URL decode -> Base64 decode -> Inflate (no header)
        url_decoded = urllib.parse.unquote(encoded_text)
        data = base64.b64decode(url_decoded)
        # -15 for raw deflate (no zlib header)
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        return None

def analyze_file(filepath):
    result = {
        "page_count": 0,
        "page_names": [],
        "all_text": [],
        "entity_count": 0,
        "edge_count": 0,
        "c4_shapes_detected": False,
        "file_exists": False
    }

    if not os.path.exists(filepath):
        return result
    
    result["file_exists"] = True
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Get all diagrams (pages)
        diagrams = root.findall('diagram')
        result["page_count"] = len(diagrams)
        
        all_mxcells = []

        for diag in diagrams:
            result["page_names"].append(diag.get('name', ''))
            
            # Content might be compressed in text node OR directly as children (uncompressed)
            if diag.text and diag.text.strip():
                content = decode_drawio_content(diag.text)
                if content:
                    diag_root = ET.fromstring(content)
                    all_mxcells.extend(diag_root.findall('.//mxCell'))
            else:
                # Uncompressed format
                all_mxcells.extend(diag.findall('.//mxCell'))
        
        # Analyze cells
        for cell in all_mxcells:
            value = cell.get('value', '')
            style = cell.get('style', '')
            vertex = cell.get('vertex')
            edge = cell.get('edge')
            
            # Extract text
            if value:
                # Clean HTML tags if present
                clean_text = ''.join(ET.fromstring(f"<root>{value}</root>").itertext()) if '<' in value else value
                result["all_text"].append(clean_text.lower())
            
            # Count shapes
            if vertex == '1':
                result["entity_count"] += 1
                # Check for C4 shapes in style string
                if 'c4' in style.lower() or 'mscgen' in style.lower(): 
                    # Note: mscgen is sometimes used, but specifically check for custom C4 libs
                    # draw.io C4 library often puts 'shape=mxgraph.c4' or similar
                    pass 
                if 'shape=' in style.lower():
                     result["c4_shapes_detected"] = True # General shape detection check

            # Count edges
            if edge == '1':
                result["edge_count"] += 1

    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    filepath = sys.argv[1]
    analysis = analyze_file(filepath)
    print(json.dumps(analysis))
PYEOF

# Run the python parser
if [ -f "$DRAWIO_FILE" ]; then
    ANALYSIS_JSON=$(python3 /tmp/parse_drawio.py "$DRAWIO_FILE")
else
    ANALYSIS_JSON='{"file_exists": false}'
fi

# Check PDF export
if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_FILE")
    # Check modification time
    PDF_MTIME=$(stat -c %Y "$PDF_FILE")
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_FRESH="true"
    else
        PDF_FRESH="false"
    fi
else
    PDF_EXISTS="false"
    PDF_SIZE="0"
    PDF_FRESH="false"
fi

# Check DRAWIO file modification
if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$DRAWIO_MTIME" -gt "$TASK_START" ]; then
        DRAWIO_FRESH="true"
    else
        DRAWIO_FRESH="false"
    fi
else
    DRAWIO_FRESH="false"
fi

# Construct final result JSON
cat > /tmp/task_result.json << EOF
{
    "analysis": $ANALYSIS_JSON,
    "pdf_export": {
        "exists": $PDF_EXISTS,
        "size": $PDF_SIZE,
        "created_during_task": $PDF_FRESH
    },
    "drawio_file": {
        "modified_during_task": $DRAWIO_FRESH,
        "path": "$DRAWIO_FILE"
    },
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json