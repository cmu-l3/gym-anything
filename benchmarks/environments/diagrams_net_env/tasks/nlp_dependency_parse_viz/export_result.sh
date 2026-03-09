#!/bin/bash
echo "=== Exporting NLP Dependency Parse Result ==="

# 1. Capture Final State
# ----------------------
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Analyze .drawio File
# ----------------------------------------
# We embed a python script to handle the XML parsing and decoding
# of the draw.io file format (which is often deflated/compressed).

cat > /tmp/analyze_drawio.py << 'PYEOF'
import sys
import os
import zlib
import base64
import json
import urllib.parse
import xml.etree.ElementTree as ET

def decode_diagram_data(raw_data):
    """Decode the draw.io compressed XML format."""
    try:
        # Standard draw.io compression: URL decode -> Base64 decode -> Inflate (no header)
        decoded = base64.b64decode(urllib.parse.unquote(raw_data))
        xml_str = zlib.decompress(decoded, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        return None

def analyze_file(filepath):
    if not os.path.exists(filepath):
        return {"exists": False}

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Determine if file is compressed or plain XML
        # draw.io files are <mxfile><diagram>COMPRESSED_DATA</diagram></mxfile>
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            content = decode_diagram_data(diagram_node.text)
            if content:
                root = ET.fromstring(content)
        
        # Now analyze the graph model (root -> root -> mxCell)
        cells = root.findall(".//mxCell")
        
        texts = []
        edges = []
        styles = []
        
        for cell in cells:
            value = cell.get('value', '')
            style = cell.get('style', '')
            
            # Collect text labels (vertices)
            if cell.get('vertex') == '1':
                if value and value.strip():
                    # Check for font color in style (red highlight)
                    is_red = False
                    if 'fontColor=#FF0000' in style or 'fontColor=red' in style:
                        is_red = True
                    # Also check spans if HTML formatting is used
                    if 'color: rgb(255, 0, 0)' in value or 'color: #FF0000' in value:
                        is_red = True
                        
                    texts.append({
                        "text": value, 
                        "is_red": is_red,
                        "x": float(cell.find('mxGeometry').get('x', 0)) if cell.find('mxGeometry') is not None else 0
                    })
            
            # Collect edges
            if cell.get('edge') == '1':
                source = cell.get('source')
                target = cell.get('target')
                if source and target:
                    is_curved = 'curved=1' in style or 'edgeStyle=orthogonalEdgeStyle' in style
                    edges.append({
                        "value": value,
                        "style": style,
                        "is_curved": is_curved
                    })

        return {
            "exists": True,
            "size": os.path.getsize(filepath),
            "mtime": os.path.getmtime(filepath),
            "texts": texts,
            "edges": edges,
            "text_count": len(texts),
            "edge_count": len(edges)
        }
        
    except Exception as e:
        return {"exists": True, "error": str(e)}

result = analyze_file("/home/ga/Diagrams/dependency_parse.drawio")
print(json.dumps(result))
PYEOF

# 3. Run Analysis and Check PDF
# -----------------------------
echo "Analyzing draw.io file..."
ANALYSIS_JSON=$(python3 /tmp/analyze_drawio.py)

# Check PDF
PDF_PATH="/home/ga/Diagrams/dependency_parse.pdf"
PDF_EXISTS="false"
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH")
else
    PDF_SIZE=0
    PDF_MTIME=0
fi

# 4. Compile Final JSON
# ---------------------
# Combine bash checks and python analysis
jq -n \
    --argjson analysis "$ANALYSIS_JSON" \
    --arg pdf_exists "$PDF_EXISTS" \
    --argjson pdf_size "$PDF_SIZE" \
    --argjson pdf_mtime "$PDF_MTIME" \
    --argjson task_start "$TASK_START" \
    --argjson task_end "$TASK_END" \
    '{
        drawio_analysis: $analysis,
        pdf_export: {
            exists: ($pdf_exists == "true"),
            size: $pdf_size,
            mtime: $pdf_mtime
        },
        task_timing: {
            start: $task_start,
            end: $task_end
        }
    }' > /tmp/task_result.json

# Cleanup
rm -f /tmp/analyze_drawio.py

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="